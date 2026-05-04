package session

import (
	"context"
	"errors"
	"fmt"
	"hash/fnv"
	"math"
	"math/rand"
	"sort"
	"strings"
	"time"

	"github.com/google/uuid"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/bson/primitive"

	"gamehub/game-session-service/internal/wallet"
)

const (
	roomVisibilityPublic  = "PUBLIC"
	roomVisibilityPrivate = "PRIVATE"

	roomStateWaiting = "WAITING"
	roomStateInRound = "IN_ROUND"

	dicePickWindow = 15 * time.Second
	diceRollWindow = 10 * time.Second
	coinFlipWindow = 10 * time.Second
)

var (
	errRoomNotFound         = errors.New("room not found")
	errRoomFull             = errors.New("room is full")
	errRoundAlreadyActive   = errors.New("round already active")
	errRoundNotActive       = errors.New("no active round")
	errNotRoomHost          = errors.New("only the room host can perform this action")
	errNotRoomMember        = errors.New("you are not in this room")
	errNeedMorePlayers      = errors.New("need at least 2 ready players")
	errCannotLeaveInRound   = errors.New("cannot leave during an active round")
	errCannotKickInRound    = errors.New("cannot remove players during an active round")
	errCannotKickHost       = errors.New("host cannot remove themselves from the room")
	errKickTargetNotFound   = errors.New("target player is not in the room")
	errInvalidRoomGame      = errors.New("unsupported room game")
	errInvalidRoomAction    = errors.New("invalid action for this game")
	errPlayerNotInRound     = errors.New("player is not part of this round")
	errAlreadySubmittedMove = errors.New("action already submitted for this round")
)

var (
	guestNameAdjectives = []string{
		"Arcade", "Blaze", "Cosmic", "Flash", "Grid", "Lucky", "Neon", "Nova",
		"Pixel", "Prime", "Rapid", "Rocket", "Turbo", "Vector", "Victory", "Volt",
	}
	guestNameNouns = []string{
		"Ace", "Pilot", "Player", "Rider", "Runner", "Spinner", "Trader", "Winner",
	}
)

var allowedRoomGames = map[string]struct{}{
	"RPS_CLASH":     {},
	"DICE_DUEL":     {},
	"TARGET_STRIKE": {},
	"HIGH_CARD":     {},
	"PARITY_CLASH":  {},
	"COIN_TOSS":     {},
	"TREASURE_BOX":  {},
	"SECRET_BID":    {},
	"SPIN_BOTTLE":   {},
	"LOOT_BOX_POOL": {},
}

type CreateRoomRequest struct {
	GameKey    string  `json:"gameKey"`
	Visibility string  `json:"visibility"`
	MinPlayers int     `json:"minPlayers"`
	MaxPlayers int     `json:"maxPlayers"`
	StakeUsd   float64 `json:"stakeUsd"`
}

type JoinRoomRequest struct {
	RoomCode string `json:"roomCode"`
}

type ListPublicRoomsRequest struct {
	GameKey string `json:"gameKey"`
}

type SetRoomReadyRequest struct {
	Ready bool `json:"ready"`
}

type UpdateRoomStakeRequest struct {
	StakeUsd float64 `json:"stakeUsd"`
}

type SubmitRoomActionRequest struct {
	Action map[string]interface{} `json:"action"`
}

type InviteToRoomRequest struct {
	TargetUserID string `json:"targetUserId"`
}

type AvailableRoomPlayer struct {
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
}

type KickRoomPlayerRequest struct {
	TargetUserID string `json:"targetUserId"`
}

type RoomPlayerSnapshot struct {
	UserID      string    `json:"userId"`
	DisplayName string    `json:"displayName"`
	Ready       bool      `json:"ready"`
	JoinedAt    time.Time `json:"joinedAt"`
}

type RoomStateSnapshot struct {
	RoomCode   string               `json:"roomCode"`
	GameKey    string               `json:"gameKey"`
	Visibility string               `json:"visibility"`
	HostUserID string               `json:"hostUserId"`
	MinPlayers int                  `json:"minPlayers"`
	MaxPlayers int                  `json:"maxPlayers"`
	StakeUsd   float64              `json:"stakeUsd"`
	State      string               `json:"state"`
	Players    []RoomPlayerSnapshot `json:"players"`
	CreatedAt  time.Time            `json:"createdAt"`
	UpdatedAt  time.Time            `json:"updatedAt"`
}

type RoomSummary struct {
	RoomCode        string    `json:"roomCode"`
	GameKey         string    `json:"gameKey"`
	HostUserID      string    `json:"hostUserId"`
	HostDisplayName string    `json:"hostDisplayName"`
	PlayerCount     int       `json:"playerCount"`
	MinPlayers      int       `json:"minPlayers"`
	MaxPlayers      int       `json:"maxPlayers"`
	StakeUsd        float64   `json:"stakeUsd"`
	CreatedAt       time.Time `json:"createdAt"`
	UpdatedAt       time.Time `json:"updatedAt"`
}

type RoomRoundStartedPayload struct {
	RoomCode         string             `json:"roomCode"`
	RoundID          string             `json:"roundId"`
	GameKey          string             `json:"gameKey"`
	RequiresAction   bool               `json:"requiresAction"`
	ActionHint       string             `json:"actionHint"`
	ActionCount      int                `json:"actionCount"`
	PlayerCount      int                `json:"playerCount"`
	StakeUsd         float64            `json:"stakeUsd"`
	PotUsd           float64            `json:"potUsd"`
	CommissionUsd    float64            `json:"commissionUsd"`
	DistributableUsd float64            `json:"distributableUsd"`
	Choices          []RoomPlayerChoice `json:"choices"`
	StartedAt        time.Time          `json:"startedAt"`
	ActionDeadline   *time.Time         `json:"actionDeadline,omitempty"`
	RollDeadline     *time.Time         `json:"rollDeadline,omitempty"`
}

type RoomPlayerChoice struct {
	UserID      string `json:"userId"`
	DisplayName string `json:"displayName"`
	Submitted   bool   `json:"submitted"`
	Revealed    bool   `json:"revealed"`
	Choice      string `json:"choice"`
}

type RoomWinnerPayout struct {
	UserID      string  `json:"userId"`
	DisplayName string  `json:"displayName"`
	PayoutUsd   float64 `json:"payoutUsd"`
	NewBalance  float64 `json:"newBalance"`
}

type RoomRoundResultPayload struct {
	RoomCode           string                 `json:"roomCode"`
	RoundID            string                 `json:"roundId"`
	GameKey            string                 `json:"gameKey"`
	StakeUsd           float64                `json:"stakeUsd"`
	PotUsd             float64                `json:"potUsd"`
	CommissionUsd      float64                `json:"commissionUsd"`
	DistributableUsd   float64                `json:"distributableUsd"`
	PayoutPerWinnerUsd float64                `json:"payoutPerWinnerUsd"`
	WinnerUserIDs      []string               `json:"winnerUserIds"`
	Winners            []RoomWinnerPayout     `json:"winners"`
	Summary            string                 `json:"summary"`
	Detail             map[string]interface{} `json:"detail"`
	Choices            []RoomPlayerChoice     `json:"choices"`
	CompletedAt        time.Time              `json:"completedAt"`
	ParticipantCount   int                    `json:"participantCount"`
	PlatformCutPercent float64                `json:"platformCutPercent"`
}

type multiplayerRoom struct {
	Code       string
	GameKey    string
	Visibility string
	HostUserID string
	MinPlayers int
	MaxPlayers int
	StakeUsd   float64
	State      string

	Players     map[string]*roomPlayer
	PlayerOrder []string
	Round       *roomRound

	CreatedAt time.Time
	UpdatedAt time.Time
}

type roomPlayer struct {
	UserID      string
	DisplayName string
	Ready       bool
	JoinedAt    time.Time
}

type roomRound struct {
	ID           string
	GameKey      string
	Status       string
	StartedAt    time.Time
	TargetNumber int

	Participants        map[string]*roundParticipant
	SettledParticipants map[string]*roundParticipant
	Actions             map[string]map[string]interface{}
	ActionDeadline      time.Time
	RollDeadline        time.Time
	TieBreakerRound     int
}

type roundParticipant struct {
	UserID      string
	DisplayName string
	SessionID   string
	StakeUsd    float64
}

func (m *Manager) CreateRoom(ctx context.Context, userID string, req CreateRoomRequest) (*RoomStateSnapshot, error) {
	gameKey := strings.ToUpper(strings.TrimSpace(req.GameKey))
	if _, ok := allowedRoomGames[gameKey]; !ok {
		return nil, errInvalidRoomGame
	}

	visibility := strings.ToUpper(strings.TrimSpace(req.Visibility))
	if visibility != roomVisibilityPublic {
		visibility = roomVisibilityPrivate
	}

	minPlayers := req.MinPlayers
	maxPlayers := req.MaxPlayers
	if minPlayers < 2 {
		minPlayers = 2
	}
	if maxPlayers < minPlayers {
		maxPlayers = minPlayers
	}
	if maxPlayers > 4 {
		maxPlayers = 4
	}
	if minPlayers > 4 {
		minPlayers = 4
	}

	stake := req.StakeUsd
	if stake <= 0 {
		stake = 1
	}
	stake = roundMoney(stake)

	displayName := m.displayNameForUser(ctx, userID)

	m.roomsMu.Lock()
	now := time.Now().UTC()
	var previousSnapshot *RoomStateSnapshot
	var previousMemberIDs []string
	if previousCode, already := m.userRooms[userID]; already {
		if previousRoom, exists := m.rooms[previousCode]; exists {
			if previousRoom.State == roomStateInRound {
				m.roomsMu.Unlock()
				return nil, errCannotLeaveInRound
			}
			delete(previousRoom.Players, userID)
			delete(m.userRooms, userID)
			previousRoom.PlayerOrder = withoutUser(previousRoom.PlayerOrder, userID)
			previousRoom.UpdatedAt = now
			if len(previousRoom.Players) == 0 {
				delete(m.rooms, previousCode)
			} else {
				if previousRoom.HostUserID == userID && len(previousRoom.PlayerOrder) > 0 {
					previousRoom.HostUserID = previousRoom.PlayerOrder[0]
				}
				snapshot := previousRoom.snapshot()
				previousSnapshot = &snapshot
				previousMemberIDs = previousRoom.memberIDs()
			}
		} else {
			delete(m.userRooms, userID)
		}
	}

	code := m.nextRoomCode()
	room := &multiplayerRoom{
		Code:       code,
		GameKey:    gameKey,
		Visibility: visibility,
		HostUserID: userID,
		MinPlayers: minPlayers,
		MaxPlayers: maxPlayers,
		StakeUsd:   stake,
		State:      roomStateWaiting,
		Players: map[string]*roomPlayer{
			userID: {
				UserID:      userID,
				DisplayName: displayName,
				Ready:       false,
				JoinedAt:    now,
			},
		},
		PlayerOrder: []string{userID},
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	m.rooms[code] = room
	m.userRooms[userID] = code

	snapshot := room.snapshot()
	m.roomsMu.Unlock()

	if previousSnapshot != nil && len(previousMemberIDs) > 0 {
		m.broadcastRoomState(previousMemberIDs, *previousSnapshot)
	}
	return &snapshot, nil
}

func (m *Manager) ListPublicRooms(req ListPublicRoomsRequest) []RoomSummary {
	gameFilter := strings.ToUpper(strings.TrimSpace(req.GameKey))

	m.roomsMu.RLock()
	defer m.roomsMu.RUnlock()

	items := make([]RoomSummary, 0, len(m.rooms))
	for _, room := range m.rooms {
		if room.Visibility != roomVisibilityPublic {
			continue
		}
		if room.State != roomStateWaiting {
			continue
		}
		if len(room.Players) >= room.MaxPlayers {
			continue
		}
		if gameFilter != "" && room.GameKey != gameFilter {
			continue
		}

		hostName := fallbackDisplayNameForUser(room.HostUserID)
		if host, ok := room.Players[room.HostUserID]; ok {
			hostName = host.DisplayName
		}
		items = append(items, RoomSummary{
			RoomCode:        room.Code,
			GameKey:         room.GameKey,
			HostUserID:      room.HostUserID,
			HostDisplayName: hostName,
			PlayerCount:     len(room.Players),
			MinPlayers:      room.MinPlayers,
			MaxPlayers:      room.MaxPlayers,
			StakeUsd:        room.StakeUsd,
			CreatedAt:       room.CreatedAt,
			UpdatedAt:       room.UpdatedAt,
		})
	}
	return items
}

func (m *Manager) JoinRoom(ctx context.Context, userID string, req JoinRoomRequest) (*RoomStateSnapshot, error) {
	roomCode := strings.ToUpper(strings.TrimSpace(req.RoomCode))
	if roomCode == "" {
		return nil, errRoomNotFound
	}
	displayName := m.displayNameForUser(ctx, userID)

	m.roomsMu.Lock()
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if existing, inRoom := m.userRooms[userID]; inRoom {
		if existing == roomCode {
			snapshot := room.snapshot()
			m.roomsMu.Unlock()
			return &snapshot, nil
		}
	}
	if len(room.Players) >= room.MaxPlayers {
		m.roomsMu.Unlock()
		return nil, errRoomFull
	}
	if room.State != roomStateWaiting {
		m.roomsMu.Unlock()
		return nil, errRoundAlreadyActive
	}

	now := time.Now().UTC()
	var previousSnapshot *RoomStateSnapshot
	var previousMemberIDs []string
	if previousCode, inRoom := m.userRooms[userID]; inRoom && previousCode != roomCode {
		if previousRoom, exists := m.rooms[previousCode]; exists {
			if previousRoom.State == roomStateInRound {
				m.roomsMu.Unlock()
				return nil, errCannotLeaveInRound
			}
			delete(previousRoom.Players, userID)
			previousRoom.PlayerOrder = withoutUser(previousRoom.PlayerOrder, userID)
			previousRoom.UpdatedAt = now
			if len(previousRoom.Players) == 0 {
				delete(m.rooms, previousCode)
			} else {
				if previousRoom.HostUserID == userID && len(previousRoom.PlayerOrder) > 0 {
					previousRoom.HostUserID = previousRoom.PlayerOrder[0]
				}
				snapshot := previousRoom.snapshot()
				previousSnapshot = &snapshot
				previousMemberIDs = previousRoom.memberIDs()
			}
		}
		delete(m.userRooms, userID)
	}
	room.Players[userID] = &roomPlayer{
		UserID:      userID,
		DisplayName: displayName,
		Ready:       false,
		JoinedAt:    now,
	}
	room.PlayerOrder = append(room.PlayerOrder, userID)
	room.UpdatedAt = now
	m.userRooms[userID] = room.Code
	snapshot := room.snapshot()
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	if previousSnapshot != nil && len(previousMemberIDs) > 0 {
		m.broadcastRoomState(previousMemberIDs, *previousSnapshot)
	}
	m.broadcastRoomState(memberIDs, snapshot)
	return &snapshot, nil
}

func (m *Manager) LeaveRoom(userID string) (*RoomStateSnapshot, error) {
	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		delete(m.userRooms, userID)
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.State == roomStateInRound {
		m.roomsMu.Unlock()
		return nil, errCannotLeaveInRound
	}

	delete(room.Players, userID)
	delete(m.userRooms, userID)
	room.PlayerOrder = withoutUser(room.PlayerOrder, userID)
	room.UpdatedAt = time.Now().UTC()

	if len(room.Players) == 0 {
		delete(m.rooms, roomCode)
		m.roomsMu.Unlock()
		return nil, nil
	}
	if room.HostUserID == userID {
		room.HostUserID = room.PlayerOrder[0]
	}

	snapshot := room.snapshot()
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	m.broadcastRoomState(memberIDs, snapshot)
	return &snapshot, nil
}

func (m *Manager) SetRoomReady(userID string, req SetRoomReadyRequest) (*RoomStateSnapshot, error) {
	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.State != roomStateWaiting {
		m.roomsMu.Unlock()
		return nil, errRoundAlreadyActive
	}
	player, ok := room.Players[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	player.Ready = req.Ready
	room.UpdatedAt = time.Now().UTC()
	snapshot := room.snapshot()
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	m.broadcastRoomState(memberIDs, snapshot)
	return &snapshot, nil
}

func (m *Manager) UpdateRoomStake(userID string, req UpdateRoomStakeRequest) (*RoomStateSnapshot, error) {
	stake := roundMoney(req.StakeUsd)
	if stake <= 0 {
		return nil, ErrInvalidStake
	}

	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.HostUserID != userID {
		m.roomsMu.Unlock()
		return nil, errNotRoomHost
	}
	if room.State == roomStateInRound || room.Round != nil {
		m.roomsMu.Unlock()
		return nil, errRoundAlreadyActive
	}

	room.StakeUsd = stake
	room.UpdatedAt = time.Now().UTC()
	for _, player := range room.Players {
		player.Ready = false
	}
	snapshot := room.snapshot()
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	m.broadcastRoomState(memberIDs, snapshot)
	return &snapshot, nil
}

func (m *Manager) GetUserRoomSnapshot(userID string) (*RoomStateSnapshot, bool) {
	m.roomsMu.RLock()
	defer m.roomsMu.RUnlock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		return nil, false
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		return nil, false
	}
	snapshot := room.snapshot()
	return &snapshot, true
}

func (m *Manager) InviteToRoom(userID string, req InviteToRoomRequest) error {
	target := strings.TrimSpace(req.TargetUserID)
	if target == "" {
		return errors.New("targetUserId is required")
	}

	m.roomsMu.RLock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.RUnlock()
		return errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.RUnlock()
		return errRoomNotFound
	}
	summary := RoomSummary{
		RoomCode:        room.Code,
		GameKey:         room.GameKey,
		HostUserID:      room.HostUserID,
		HostDisplayName: fallbackDisplayNameForUser(room.HostUserID),
		PlayerCount:     len(room.Players),
		MinPlayers:      room.MinPlayers,
		MaxPlayers:      room.MaxPlayers,
		StakeUsd:        room.StakeUsd,
		CreatedAt:       room.CreatedAt,
		UpdatedAt:       room.UpdatedAt,
	}
	if host, exists := room.Players[room.HostUserID]; exists {
		summary.HostDisplayName = host.DisplayName
	}
	inviterName := fallbackDisplayNameForUser(userID)
	if inviter, exists := room.Players[userID]; exists {
		inviterName = inviter.DisplayName
	}
	m.roomsMu.RUnlock()

	m.broadcast(target, map[string]interface{}{
		"type": "ROOM_INVITE",
		"payload": map[string]interface{}{
			"room":         summary,
			"fromUserId":   userID,
			"fromUserName": inviterName,
		},
	})
	return nil
}

func (m *Manager) ListAvailableRoomPlayers(ctx context.Context, userID string) []AvailableRoomPlayer {
	m.mu.RLock()
	userIDs := make([]string, 0, len(m.subscribers))
	for uid, subs := range m.subscribers {
		if uid == userID || len(subs) == 0 {
			continue
		}
		userIDs = append(userIDs, uid)
	}
	m.mu.RUnlock()

	m.roomsMu.RLock()
	occupiedRooms := make(map[string]string, len(m.userRooms))
	for uid, roomCode := range m.userRooms {
		occupiedRooms[uid] = roomCode
	}
	m.roomsMu.RUnlock()

	sort.Strings(userIDs)
	players := make([]AvailableRoomPlayer, 0, len(userIDs))
	for _, uid := range userIDs {
		roomCode := occupiedRooms[uid]
		if roomCode != "" {
			// Do not invite users already seated in this or another room.
			continue
		}
		players = append(players, AvailableRoomPlayer{
			UserID:      uid,
			DisplayName: m.displayNameForUser(ctx, uid),
		})
		if len(players) >= 20 {
			break
		}
	}
	return players
}

func (m *Manager) KickRoomPlayer(userID string, req KickRoomPlayerRequest) (*RoomStateSnapshot, error) {
	target := strings.TrimSpace(req.TargetUserID)
	if target == "" {
		return nil, errors.New("targetUserId is required")
	}

	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.HostUserID != userID {
		m.roomsMu.Unlock()
		return nil, errNotRoomHost
	}
	if room.State == roomStateInRound {
		m.roomsMu.Unlock()
		return nil, errCannotKickInRound
	}
	if target == room.HostUserID {
		m.roomsMu.Unlock()
		return nil, errCannotKickHost
	}
	if _, exists := room.Players[target]; !exists {
		m.roomsMu.Unlock()
		return nil, errKickTargetNotFound
	}

	delete(room.Players, target)
	delete(m.userRooms, target)
	room.PlayerOrder = withoutUser(room.PlayerOrder, target)
	room.UpdatedAt = time.Now().UTC()

	snapshot := room.snapshot()
	memberIDs := room.memberIDs()
	gameKey := room.GameKey
	m.roomsMu.Unlock()

	m.broadcast(target, map[string]interface{}{
		"type": "ROOM_KICKED",
		"payload": map[string]interface{}{
			"roomCode": roomCode,
			"gameKey":  gameKey,
			"message":  "Host removed you from the room",
		},
	})
	m.broadcastRoomState(memberIDs, snapshot)
	return &snapshot, nil
}

func (m *Manager) StartRoomRound(ctx context.Context, userID string, nextStakeUsd float64) (*RoomRoundStartedPayload, error) {
	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.HostUserID != userID {
		m.roomsMu.Unlock()
		return nil, errNotRoomHost
	}
	if room.State == roomStateInRound || room.Round != nil {
		m.roomsMu.Unlock()
		return nil, errRoundAlreadyActive
	}
	if nextStakeUsd > 0 {
		room.StakeUsd = roundMoney(nextStakeUsd)
	}
	if host := room.Players[userID]; host != nil {
		host.Ready = true
	}

	readyPlayers := make([]*roomPlayer, 0, len(room.Players))
	for _, id := range room.PlayerOrder {
		player := room.Players[id]
		if player != nil && player.Ready {
			readyPlayers = append(readyPlayers, player)
		}
	}
	if len(readyPlayers) < room.MinPlayers || len(readyPlayers) < 2 {
		m.roomsMu.Unlock()
		return nil, errNeedMorePlayers
	}
	if len(readyPlayers) > room.MaxPlayers {
		readyPlayers = readyPlayers[:room.MaxPlayers]
	}

	participants := make(map[string]*roundParticipant, len(readyPlayers))
	for _, p := range readyPlayers {
		participants[p.UserID] = &roundParticipant{
			UserID:      p.UserID,
			DisplayName: p.DisplayName,
			StakeUsd:    room.StakeUsd,
		}
	}

	roundID := uuid.NewString()
	actionDeadline := time.Time{}
	if room.GameKey == "DICE_DUEL" {
		actionDeadline = time.Now().UTC().Add(dicePickWindow)
	}
	room.Round = &roomRound{
		ID:                  roundID,
		GameKey:             room.GameKey,
		Status:              "COLLECTING_ACTIONS",
		StartedAt:           time.Now().UTC(),
		TargetNumber:        rand.Intn(100),
		Participants:        participants,
		SettledParticipants: cloneRoundParticipants(participants),
		Actions:             make(map[string]map[string]interface{}),
		ActionDeadline:      actionDeadline,
		TieBreakerRound:     1,
	}
	if !requiresAction(room.GameKey) {
		room.Round.Status = "RESOLVING"
	}
	room.State = roomStateInRound
	room.UpdatedAt = time.Now().UTC()
	memberIDs := room.memberIDs()
	gameKey := room.GameKey
	stake := room.StakeUsd
	pot := roundMoney(stake * float64(len(participants)))
	commission := roundMoney(pot * 0.15)
	distributable := roundMoney(pot - commission)
	m.roomsMu.Unlock()

	type reservedSession struct {
		userID    string
		sessionID string
		stakeUsd  float64
	}
	reserved := make([]reservedSession, 0, len(participants))
	for uid, participant := range participants {
		sessionID := primitive.NewObjectID().Hex()
		traceID := uuid.NewString()
		if _, err := m.wallet.ReserveBet(ctx, wallet.ReserveBetRequest{
			UserID:    uid,
			SessionID: sessionID,
			GameType:  "MULTI_" + gameKey,
			AmountUsd: participant.StakeUsd,
			TraceID:   traceID,
		}); err != nil {
			for _, refund := range reserved {
				refundTrace := uuid.NewString()
				bal, settleErr := m.wallet.SettleGame(context.Background(), wallet.SettleGameRequest{
					UserID:    refund.userID,
					SessionID: refund.sessionID,
					Outcome:   "REFUND",
					StakeUsd:  refund.stakeUsd,
					PayoutUsd: refund.stakeUsd,
					TraceID:   refundTrace,
				})
				if settleErr == nil {
					outcome := SessionOutcome{
						SessionID:    refund.sessionID,
						UserID:       refund.userID,
						GameType:     "MULTI_" + gameKey,
						Outcome:      "REFUND",
						PayoutUsd:    refund.stakeUsd,
						WinAmountUsd: 0,
						StakeUsd:     refund.stakeUsd,
						NewBalance:   bal.AvailableUsd,
						TraceID:      refundTrace,
						ContractID:   "REFUND",
					}
					m.persistOutcome(context.Background(), outcome)
					m.broadcast(refund.userID, wsMessage("GAME_RESULT", outcome))
				}
			}
			m.roomsMu.Lock()
			if roomRef, exists := m.rooms[roomCode]; exists {
				roomRef.Round = nil
				roomRef.State = roomStateWaiting
				roomRef.UpdatedAt = time.Now().UTC()
				for _, p := range roomRef.Players {
					p.Ready = false
				}
				snapshot := roomRef.snapshot()
				memberIDs = roomRef.memberIDs()
				m.roomsMu.Unlock()
				m.broadcastRoomState(memberIDs, snapshot)
				return nil, fmt.Errorf("reserve failed for player %s: %w", uid, err)
			}
			m.roomsMu.Unlock()
			return nil, err
		}

		participant.SessionID = sessionID
		reserved = append(reserved, reservedSession{
			userID:    uid,
			sessionID: sessionID,
			stakeUsd:  participant.StakeUsd,
		})

		now := time.Now().UTC()
		doc := bson.M{
			"sessionId":  sessionID,
			"userId":     uid,
			"gameType":   "MULTI_" + gameKey,
			"stakeUsd":   participant.StakeUsd,
			"prediction": bson.M{"roomCode": roomCode, "roundId": roundID},
			"traceId":    traceID,
			"status":     "PENDING",
			"createdAt":  now,
			"updatedAt":  now,
		}
		_, _ = m.db.Collection("game_sessions").InsertOne(context.Background(), doc)
	}

	payload := &RoomRoundStartedPayload{
		RoomCode:         roomCode,
		RoundID:          roundID,
		GameKey:          gameKey,
		RequiresAction:   requiresAction(gameKey),
		ActionHint:       actionHint(gameKey),
		ActionCount:      0,
		PlayerCount:      len(participants),
		StakeUsd:         stake,
		PotUsd:           pot,
		CommissionUsd:    commission,
		DistributableUsd: distributable,
		Choices:          roomRoundChoices(gameKey, participants, map[string]map[string]interface{}{}),
		StartedAt:        time.Now().UTC(),
	}
	if !actionDeadline.IsZero() {
		payload.ActionDeadline = &actionDeadline
	}

	m.broadcastRoomRoundStarted(memberIDs, *payload)

	if !requiresAction(gameKey) {
		resolveCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_, _ = m.ResolveRoomRound(resolveCtx, roomCode, roundID)
	}
	if gameKey == "DICE_DUEL" {
		m.scheduleDicePickDeadline(roomCode, roundID, actionDeadline)
	}

	_ = stake // explicit: stake is included in snapshot events and used during reserves.
	return payload, nil
}

func (m *Manager) SubmitRoomAction(ctx context.Context, userID string, req SubmitRoomActionRequest) (*RoomRoundStartedPayload, error) {
	m.roomsMu.Lock()
	roomCode, ok := m.userRooms[userID]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errNotRoomMember
	}
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.Round == nil || room.State != roomStateInRound {
		m.roomsMu.Unlock()
		return nil, errRoundNotActive
	}
	round := room.Round
	if round.Status != "COLLECTING_ACTIONS" {
		m.roomsMu.Unlock()
		return nil, errRoundNotActive
	}
	participant, ok := round.Participants[userID]
	if !ok || participant == nil {
		m.roomsMu.Unlock()
		return nil, errPlayerNotInRound
	}
	if _, exists := round.Actions[userID]; exists {
		m.roomsMu.Unlock()
		return nil, errAlreadySubmittedMove
	}

	action, err := normalizeAction(round.GameKey, req.Action)
	if err != nil {
		m.roomsMu.Unlock()
		return nil, err
	}
	round.Actions[userID] = action
	room.UpdatedAt = time.Now().UTC()

	actionCount := len(round.Actions)
	playerCount := len(round.Participants)
	stake := 0.0
	for _, p := range round.Participants {
		stake = p.StakeUsd
		break
	}
	pot := roundMoney(stake * float64(playerCount))
	commission := roundMoney(pot * 0.15)
	distributable := roundMoney(pot - commission)
	payload := &RoomRoundStartedPayload{
		RoomCode:         roomCode,
		RoundID:          round.ID,
		GameKey:          round.GameKey,
		RequiresAction:   true,
		ActionHint:       actionHint(round.GameKey),
		ActionCount:      actionCount,
		PlayerCount:      playerCount,
		StakeUsd:         stake,
		PotUsd:           pot,
		CommissionUsd:    commission,
		DistributableUsd: distributable,
		Choices:          roomRoundChoices(round.GameKey, round.Participants, round.Actions),
		StartedAt:        round.StartedAt,
	}
	if !round.ActionDeadline.IsZero() {
		deadline := round.ActionDeadline
		payload.ActionDeadline = &deadline
	}
	memberIDs := room.memberIDs()
	shouldResolve := actionCount >= playerCount
	shouldStartDiceRoll := round.GameKey == "DICE_DUEL" && shouldResolve
	shouldStartCoinFlip := round.GameKey == "COIN_TOSS" && shouldResolve
	roundID := round.ID
	m.roomsMu.Unlock()

	m.broadcastRoomRoundStarted(memberIDs, *payload)

	if shouldStartDiceRoll {
		m.startDiceRoll(roomCode, roundID)
	} else if shouldStartCoinFlip {
		m.startCoinFlip(roomCode, roundID)
	} else if shouldResolve {
		resolveCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		defer cancel()
		_, _ = m.ResolveRoomRound(resolveCtx, roomCode, roundID)
	}
	return payload, nil
}

func (m *Manager) ResolveRoomRound(ctx context.Context, roomCode, roundID string) (*RoomRoundResultPayload, error) {
	m.roomsMu.Lock()
	room, ok := m.rooms[roomCode]
	if !ok {
		m.roomsMu.Unlock()
		return nil, errRoomNotFound
	}
	if room.Round == nil || room.Round.ID != roundID {
		m.roomsMu.Unlock()
		return nil, errRoundNotActive
	}
	round := room.Round
	if round.Status == "RESOLVED" {
		m.roomsMu.Unlock()
		return nil, errRoundNotActive
	}
	if round.Status == "RESOLVING" && requiresAction(round.GameKey) {
		m.roomsMu.Unlock()
		return nil, errRoundNotActive
	}
	if round.GameKey == "DICE_DUEL" || round.GameKey == "COIN_TOSS" {
		if round.Status != "ROLLING" ||
			round.RollDeadline.IsZero() ||
			time.Now().UTC().Before(round.RollDeadline) {
			m.roomsMu.Unlock()
			return nil, errRoundNotActive
		}
	}
	round.Status = "RESOLVING"

	participants := make([]*roundParticipant, 0, len(round.Participants))
	for _, p := range round.Participants {
		cp := *p
		participants = append(participants, &cp)
	}
	settledParticipants := make([]*roundParticipant, 0, len(round.SettledParticipants))
	for _, p := range round.SettledParticipants {
		cp := *p
		settledParticipants = append(settledParticipants, &cp)
	}
	if len(settledParticipants) == 0 {
		settledParticipants = participants
	}
	actions := make(map[string]map[string]interface{}, len(round.Actions))
	for uid, action := range round.Actions {
		dup := make(map[string]interface{}, len(action))
		for k, v := range action {
			dup[k] = v
		}
		actions[uid] = dup
	}
	gameKey := round.GameKey
	target := round.TargetNumber
	tieBreakerRound := round.TieBreakerRound
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	var winnerIDs []string
	var summary string
	var detail map[string]interface{}
	if gameKey == "DICE_DUEL" {
		winnerIDs, summary, detail = evaluateDice(participants, actions)
		detail["tieBreakerRound"] = tieBreakerRound
		choices := roomResultChoices(gameKey, participants, actions, detail)
		if len(winnerIDs) != 1 {
			detail["continues"] = true
			nextParticipants := participantsByUserID(participants, winnerIDs)
			if len(nextParticipants) == 0 {
				nextParticipants = participantsByUserID(participants, participantIDs(participants))
			}
			nextDeadline := time.Now().UTC().Add(dicePickWindow)
			nextPayload := RoomRoundStartedPayload{
				RoomCode:         roomCode,
				RoundID:          roundID,
				GameKey:          gameKey,
				RequiresAction:   true,
				ActionHint:       actionHint(gameKey),
				ActionCount:      0,
				PlayerCount:      len(nextParticipants),
				StakeUsd:         stakeFromParticipants(settledParticipants),
				PotUsd:           roundMoney(totalStake(settledParticipants)),
				CommissionUsd:    roundMoney(totalStake(settledParticipants) * 0.15),
				DistributableUsd: roundMoney(totalStake(settledParticipants) * 0.85),
				Choices:          roomRoundChoices(gameKey, nextParticipants, map[string]map[string]interface{}{}),
				StartedAt:        time.Now().UTC(),
				ActionDeadline:   &nextDeadline,
			}
			result := RoomRoundResultPayload{
				RoomCode:           roomCode,
				RoundID:            roundID,
				GameKey:            gameKey,
				StakeUsd:           nextPayload.StakeUsd,
				PotUsd:             nextPayload.PotUsd,
				CommissionUsd:      nextPayload.CommissionUsd,
				DistributableUsd:   nextPayload.DistributableUsd,
				PayoutPerWinnerUsd: 0,
				WinnerUserIDs:      []string{},
				Winners:            []RoomWinnerPayout{},
				Summary:            summary,
				Detail:             detail,
				Choices:            choices,
				CompletedAt:        time.Now().UTC(),
				ParticipantCount:   len(settledParticipants),
				PlatformCutPercent: 15,
			}

			m.roomsMu.Lock()
			if roomRef, exists := m.rooms[roomCode]; exists && roomRef.Round != nil && roomRef.Round.ID == roundID {
				roomRef.Round.Participants = nextParticipants
				roomRef.Round.Actions = make(map[string]map[string]interface{})
				roomRef.Round.Status = "COLLECTING_ACTIONS"
				roomRef.Round.ActionDeadline = nextDeadline
				roomRef.Round.RollDeadline = time.Time{}
				roomRef.Round.TieBreakerRound++
				roomRef.UpdatedAt = time.Now().UTC()
				memberIDs = roomRef.memberIDs()
				m.roomsMu.Unlock()
				m.broadcastRoomRoundResult(memberIDs, result)
				m.broadcastRoomRoundStarted(memberIDs, nextPayload)
				m.scheduleDicePickDeadline(roomCode, roundID, nextDeadline)
				return &result, nil
			}
			m.roomsMu.Unlock()
			return &result, nil
		}
	} else {
		winnerIDs, summary, detail = evaluateRound(gameKey, participants, actions, target)
	}

	choices := roomResultChoices(gameKey, participants, actions, detail)
	if gameKey == "DICE_DUEL" {
		choices = diceResultChoices(settledParticipants, participants, actions, detail)
	}
	allowNoWinners := false
	if raw, ok := detail["noWinners"].(bool); ok && raw {
		allowNoWinners = true
	}
	if len(winnerIDs) == 0 && !allowNoWinners {
		for _, p := range participants {
			winnerIDs = append(winnerIDs, p.UserID)
		}
	}

	winnerSet := make(map[string]struct{}, len(winnerIDs))
	for _, uid := range winnerIDs {
		winnerSet[uid] = struct{}{}
	}

	pot := totalStake(settledParticipants)
	pot = roundMoney(pot)
	commission := roundMoney(pot * 0.15)
	distributable := roundMoney(pot - commission)
	payoutPerWinner := 0.0
	if len(winnerIDs) > 0 {
		payoutPerWinner = roundMoney(distributable / float64(len(winnerIDs)))
	}

	winners := make([]RoomWinnerPayout, 0, len(winnerIDs))
	for _, p := range settledParticipants {
		payout := 0.0
		outcome := "LOSS"
		if _, isWinner := winnerSet[p.UserID]; isWinner {
			payout = payoutPerWinner
			outcome = "WIN"
		}

		traceID := uuid.NewString()
		bal, err := m.wallet.SettleGame(ctx, wallet.SettleGameRequest{
			UserID:    p.UserID,
			SessionID: p.SessionID,
			Outcome:   outcome,
			StakeUsd:  p.StakeUsd,
			PayoutUsd: payout,
			TraceID:   traceID,
		})
		if err != nil {
			continue
		}

		winAmount := payout - p.StakeUsd
		if winAmount < 0 {
			winAmount = 0
		}
		sessionOutcome := SessionOutcome{
			SessionID:    p.SessionID,
			UserID:       p.UserID,
			GameType:     "MULTI_" + gameKey,
			Outcome:      outcome,
			PayoutUsd:    payout,
			WinAmountUsd: winAmount,
			StakeUsd:     p.StakeUsd,
			NewBalance:   bal.AvailableUsd,
			TraceID:      traceID,
			ContractID:   "MULTI_ROOM",
		}
		m.persistOutcome(context.Background(), sessionOutcome)
		m.broadcast(p.UserID, wsMessage("GAME_RESULT", sessionOutcome))

		if _, isWinner := winnerSet[p.UserID]; isWinner {
			winners = append(winners, RoomWinnerPayout{
				UserID:      p.UserID,
				DisplayName: p.DisplayName,
				PayoutUsd:   payout,
				NewBalance:  bal.AvailableUsd,
			})
		}
	}

	result := RoomRoundResultPayload{
		RoomCode:           roomCode,
		RoundID:            roundID,
		GameKey:            gameKey,
		StakeUsd:           roundMoney(pot / math.Max(float64(len(settledParticipants)), 1)),
		PotUsd:             pot,
		CommissionUsd:      commission,
		DistributableUsd:   distributable,
		PayoutPerWinnerUsd: payoutPerWinner,
		WinnerUserIDs:      winnerIDs,
		Winners:            winners,
		Summary:            summary,
		Detail:             detail,
		Choices:            choices,
		CompletedAt:        time.Now().UTC(),
		ParticipantCount:   len(participants),
		PlatformCutPercent: 15,
	}

	m.roomsMu.Lock()
	if roomRef, exists := m.rooms[roomCode]; exists {
		roomRef.Round = nil
		roomRef.State = roomStateWaiting
		roomRef.UpdatedAt = time.Now().UTC()
		for _, p := range roomRef.Players {
			p.Ready = false
		}
		snapshot := roomRef.snapshot()
		memberIDs = roomRef.memberIDs()
		m.roomsMu.Unlock()
		m.broadcastRoomRoundResult(memberIDs, result)
		m.broadcastRoomState(memberIDs, snapshot)
		return &result, nil
	}
	m.roomsMu.Unlock()

	m.broadcastRoomRoundResult(memberIDs, result)
	return &result, nil
}

func normalizeAction(gameKey string, raw map[string]interface{}) (map[string]interface{}, error) {
	if raw == nil {
		raw = map[string]interface{}{}
	}
	switch gameKey {
	case "RPS_CLASH":
		pick := strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", raw["pick"])))
		switch pick {
		case "ROCK", "PAPER", "SCISSORS":
			return map[string]interface{}{"pick": pick}, nil
		default:
			return nil, errInvalidRoomAction
		}
	case "TARGET_STRIKE":
		n, ok := asInt(raw["number"])
		if !ok || n < 0 || n > 99 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"number": n}, nil
	case "PARITY_CLASH":
		n, ok := asInt(raw["digit"])
		if !ok || n < 0 || n > 9 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"digit": n}, nil
	case "COIN_TOSS":
		side := strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", raw["side"])))
		switch side {
		case "HEADS", "TAILS":
			return map[string]interface{}{"side": side}, nil
		default:
			return nil, errInvalidRoomAction
		}
	case "TREASURE_BOX":
		n, ok := asInt(raw["box"])
		if !ok || n < 1 || n > 6 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"box": n}, nil
	case "SECRET_BID":
		n, ok := asInt(raw["bid"])
		if !ok || n < 1 || n > 100 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"bid": n}, nil
	case "SPIN_BOTTLE":
		side := strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", raw["side"])))
		switch side {
		case "LEFT", "RIGHT":
			return map[string]interface{}{"side": side}, nil
		default:
			return nil, errInvalidRoomAction
		}
	case "LOOT_BOX_POOL":
		n, ok := asInt(raw["box"])
		if !ok || n < 1 || n > 20 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"box": n}, nil
	case "DICE_DUEL":
		n, ok := asInt(raw["number"])
		if !ok || n < 1 || n > 6 {
			return nil, errInvalidRoomAction
		}
		return map[string]interface{}{"number": n}, nil
	case "HIGH_CARD":
		return map[string]interface{}{}, nil
	default:
		return nil, errInvalidRoomGame
	}
}

func roomRoundChoices(gameKey string, participants map[string]*roundParticipant, actions map[string]map[string]interface{}) []RoomPlayerChoice {
	choices := make([]RoomPlayerChoice, 0, len(participants))
	for _, participant := range participants {
		if participant == nil {
			continue
		}
		choice := RoomPlayerChoice{
			UserID:      participant.UserID,
			DisplayName: participant.DisplayName,
			Choice:      "Waiting",
		}
		if !requiresAction(gameKey) {
			choice.Submitted = true
			choice.Revealed = true
			choice.Choice = "Auto"
		} else if action, ok := actions[participant.UserID]; ok {
			choice.Submitted = true
			choice.Revealed = true
			choice.Choice = actionChoiceLabel(gameKey, action)
		}
		choices = append(choices, choice)
	}
	sort.Slice(choices, func(i, j int) bool {
		return choices[i].DisplayName < choices[j].DisplayName
	})
	return choices
}

func roomResultChoices(
	gameKey string,
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
	detail map[string]interface{},
) []RoomPlayerChoice {
	choices := make([]RoomPlayerChoice, 0, len(participants))
	for _, participant := range participants {
		if participant == nil {
			continue
		}
		label := resultChoiceLabel(gameKey, participant.UserID, actions, detail)
		choices = append(choices, RoomPlayerChoice{
			UserID:      participant.UserID,
			DisplayName: participant.DisplayName,
			Submitted:   true,
			Revealed:    true,
			Choice:      label,
		})
	}
	sort.Slice(choices, func(i, j int) bool {
		return choices[i].DisplayName < choices[j].DisplayName
	})
	return choices
}

func diceResultChoices(
	allParticipants []*roundParticipant,
	activeParticipants []*roundParticipant,
	actions map[string]map[string]interface{},
	detail map[string]interface{},
) []RoomPlayerChoice {
	activeSet := make(map[string]struct{}, len(activeParticipants))
	for _, participant := range activeParticipants {
		if participant != nil {
			activeSet[participant.UserID] = struct{}{}
		}
	}

	choices := make([]RoomPlayerChoice, 0, len(allParticipants))
	for _, participant := range allParticipants {
		if participant == nil {
			continue
		}
		label := "Eliminated"
		submitted := true
		if _, active := activeSet[participant.UserID]; active {
			label = resultChoiceLabel("DICE_DUEL", participant.UserID, actions, detail)
			if label == "Pick 0" {
				label = "No pick"
				submitted = false
			}
		}
		choices = append(choices, RoomPlayerChoice{
			UserID:      participant.UserID,
			DisplayName: participant.DisplayName,
			Submitted:   submitted,
			Revealed:    true,
			Choice:      label,
		})
	}
	sort.Slice(choices, func(i, j int) bool {
		return choices[i].DisplayName < choices[j].DisplayName
	})
	return choices
}

func resultChoiceLabel(gameKey, userID string, actions map[string]map[string]interface{}, detail map[string]interface{}) string {
	switch gameKey {
	case "RPS_CLASH":
		return labelFromDetailMap(detail, "picks", userID, "ROCK")
	case "DICE_DUEL":
		return "Pick " + labelFromDetailMap(detail, "picks", userID, "0")
	case "TARGET_STRIKE":
		return "Number " + labelFromDetailMap(detail, "picks", userID, "0")
	case "HIGH_CARD":
		return "Card " + labelFromDetailMap(detail, "cards", userID, "0")
	case "PARITY_CLASH":
		return "Digit " + labelFromDetailMap(detail, "digits", userID, "0")
	case "COIN_TOSS":
		return labelFromDetailMap(detail, "picks", userID, "HEADS")
	case "TREASURE_BOX":
		return "Box " + labelFromDetailMap(detail, "boxes", userID, "1")
	case "SECRET_BID":
		return "Bid " + labelFromDetailMap(detail, "bids", userID, "1")
	case "SPIN_BOTTLE":
		return labelFromDetailMap(detail, "picks", userID, "LEFT")
	case "LOOT_BOX_POOL":
		return "Box " + labelFromDetailMap(detail, "boxPicks", userID, "1")
	default:
		if action, ok := actions[userID]; ok {
			return actionChoiceLabel(gameKey, action)
		}
		return "Auto"
	}
}

func labelFromDetailMap(detail map[string]interface{}, key, userID, fallback string) string {
	value, ok := valueFromDetailMap(detail, key, userID)
	if !ok {
		return fallback
	}
	return strings.TrimSpace(fmt.Sprintf("%v", value))
}

func valueFromDetailMap(detail map[string]interface{}, key, userID string) (interface{}, bool) {
	if detail == nil {
		return nil, false
	}
	raw, ok := detail[key]
	if !ok {
		return nil, false
	}
	switch values := raw.(type) {
	case map[string]interface{}:
		v, exists := values[userID]
		return v, exists
	case map[string]string:
		v, exists := values[userID]
		return v, exists
	case map[string]int:
		v, exists := values[userID]
		return v, exists
	case map[string]float64:
		v, exists := values[userID]
		return v, exists
	default:
		return nil, false
	}
}

func actionChoiceLabel(gameKey string, action map[string]interface{}) string {
	switch gameKey {
	case "RPS_CLASH":
		return strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", action["pick"])))
	case "DICE_DUEL":
		return fmt.Sprintf("Pick %v", action["number"])
	case "TARGET_STRIKE":
		return fmt.Sprintf("Number %v", action["number"])
	case "PARITY_CLASH":
		return fmt.Sprintf("Digit %v", action["digit"])
	case "COIN_TOSS":
		return strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", action["side"])))
	case "TREASURE_BOX":
		return fmt.Sprintf("Box %v", action["box"])
	case "SECRET_BID":
		return fmt.Sprintf("Bid %v", action["bid"])
	case "SPIN_BOTTLE":
		return strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", action["side"])))
	case "LOOT_BOX_POOL":
		return fmt.Sprintf("Box %v", action["box"])
	default:
		return "Auto"
	}
}

func evaluateRound(
	gameKey string,
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
	target int,
) ([]string, string, map[string]interface{}) {
	switch gameKey {
	case "RPS_CLASH":
		return evaluateRPS(participants, actions)
	case "DICE_DUEL":
		return evaluateDice(participants, actions)
	case "TARGET_STRIKE":
		return evaluateTargetStrike(participants, actions, target)
	case "HIGH_CARD":
		return evaluateHighCard(participants)
	case "PARITY_CLASH":
		return evaluateParityClash(participants, actions)
	case "COIN_TOSS":
		return evaluateCoinToss(participants, actions)
	case "TREASURE_BOX":
		return evaluateTreasureBox(participants, actions)
	case "SECRET_BID":
		return evaluateSecretBid(participants, actions)
	case "SPIN_BOTTLE":
		return evaluateSpinBottle(participants, actions)
	case "LOOT_BOX_POOL":
		return evaluateLootBoxPool(participants, actions)
	default:
		winners := make([]string, 0, len(participants))
		for _, p := range participants {
			winners = append(winners, p.UserID)
		}
		return winners, "Round settled", map[string]interface{}{}
	}
}

func evaluateRPS(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	picks := make(map[string]string, len(participants))
	unique := map[string]struct{}{}
	for _, p := range participants {
		pick := "ROCK"
		if action, ok := actions[p.UserID]; ok {
			if v, exists := action["pick"]; exists {
				pick = strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", v)))
			}
		}
		if pick != "ROCK" && pick != "PAPER" && pick != "SCISSORS" {
			pick = "ROCK"
		}
		picks[p.UserID] = pick
		unique[pick] = struct{}{}
	}

	if len(unique) == 1 || len(unique) == 3 {
		winners := make([]string, 0, len(participants))
		for _, p := range participants {
			winners = append(winners, p.UserID)
		}
		return winners, "Tie table: pot split across all players", map[string]interface{}{
			"picks": picks,
		}
	}

	winningPick := "ROCK"
	_, hasRock := unique["ROCK"]
	_, hasPaper := unique["PAPER"]
	_, hasScissors := unique["SCISSORS"]
	switch {
	case hasRock && hasScissors:
		winningPick = "ROCK"
	case hasRock && hasPaper:
		winningPick = "PAPER"
	case hasPaper && hasScissors:
		winningPick = "SCISSORS"
	}

	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		if picks[p.UserID] == winningPick {
			winners = append(winners, p.UserID)
		}
	}
	return winners, fmt.Sprintf("%s wins this clash", winningPick), map[string]interface{}{
		"picks":       picks,
		"winningPick": winningPick,
	}
}

func evaluateDice(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	roll := rand.Intn(6) + 1
	picks := make(map[string]int, len(participants))
	submitted := make(map[string]bool, len(participants))
	survivors := make([]string, 0, len(participants))

	for _, p := range participants {
		pick := 0
		if action, ok := actions[p.UserID]; ok {
			if n, ok := asInt(action["number"]); ok && n >= 1 && n <= 6 {
				pick = n
				submitted[p.UserID] = true
			}
		}
		picks[p.UserID] = pick
		if pick == roll {
			survivors = append(survivors, p.UserID)
		}
	}

	summary := fmt.Sprintf("Dice landed on %d", roll)
	switch len(survivors) {
	case 0:
		summary = fmt.Sprintf("Dice landed on %d. No match, pick again", roll)
	case 1:
		summary = fmt.Sprintf("Dice landed on %d. Winner selected", roll)
	default:
		summary = fmt.Sprintf("Dice landed on %d. %d players continue", roll, len(survivors))
	}

	return survivors, summary, map[string]interface{}{
		"roll":      roll,
		"picks":     picks,
		"submitted": submitted,
		"survivors": survivors,
	}
}

func evaluateTargetStrike(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
	target int,
) ([]string, string, map[string]interface{}) {
	picks := make(map[string]int, len(participants))
	bestDiff := 1000
	for _, p := range participants {
		pick := rand.Intn(100)
		if action, ok := actions[p.UserID]; ok {
			if n, ok := asInt(action["number"]); ok && n >= 0 && n <= 99 {
				pick = n
			}
		}
		picks[p.UserID] = pick
		diff := int(math.Abs(float64(pick - target)))
		if diff < bestDiff {
			bestDiff = diff
		}
	}
	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		diff := int(math.Abs(float64(picks[p.UserID] - target)))
		if diff == bestDiff {
			winners = append(winners, p.UserID)
		}
	}
	return winners, fmt.Sprintf("Target was %d", target), map[string]interface{}{
		"target": target,
		"picks":  picks,
	}
}

func evaluateHighCard(participants []*roundParticipant) ([]string, string, map[string]interface{}) {
	cards := make(map[string]int, len(participants))
	top := 0
	for _, p := range participants {
		card := rand.Intn(13) + 1
		cards[p.UserID] = card
		if card > top {
			top = card
		}
	}
	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		if cards[p.UserID] == top {
			winners = append(winners, p.UserID)
		}
	}
	return winners, fmt.Sprintf("Top card rank: %d", top), map[string]interface{}{
		"cards": cards,
	}
}

func evaluateParityClash(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	digits := make(map[string]int, len(participants))
	sum := 0
	for _, p := range participants {
		digit := rand.Intn(10)
		if action, ok := actions[p.UserID]; ok {
			if n, ok := asInt(action["digit"]); ok && n >= 0 && n <= 9 {
				digit = n
			}
		}
		digits[p.UserID] = digit
		sum += digit
	}
	isEven := sum%2 == 0
	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		if (digits[p.UserID]%2 == 0) == isEven {
			winners = append(winners, p.UserID)
		}
	}
	label := "ODD"
	if isEven {
		label = "EVEN"
	}
	return winners, fmt.Sprintf("Sum parity resolved to %s", label), map[string]interface{}{
		"digits": digits,
		"sum":    sum,
		"parity": label,
	}
}

func evaluateCoinToss(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	picks := make(map[string]string, len(participants))
	coin := "HEADS"
	if rand.Intn(2) == 1 {
		coin = "TAILS"
	}
	for _, p := range participants {
		pick := coin
		if action, ok := actions[p.UserID]; ok {
			if v, exists := action["side"]; exists {
				value := strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", v)))
				if value == "HEADS" || value == "TAILS" {
					pick = value
				}
			}
		}
		picks[p.UserID] = pick
	}

	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		if picks[p.UserID] == coin {
			winners = append(winners, p.UserID)
		}
	}
	return winners, fmt.Sprintf("Coin landed %s", coin), map[string]interface{}{
		"coin":  coin,
		"picks": picks,
	}
}

func evaluateTreasureBox(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	picks := make(map[string]int, len(participants))
	winningBox := rand.Intn(6) + 1
	bestDiff := 100
	exact := false

	for _, p := range participants {
		pick := rand.Intn(6) + 1
		if action, ok := actions[p.UserID]; ok {
			if v, ok := asInt(action["box"]); ok && v >= 1 && v <= 6 {
				pick = v
			}
		}
		picks[p.UserID] = pick
		diff := int(math.Abs(float64(pick - winningBox)))
		if diff == 0 {
			exact = true
		}
		if diff < bestDiff {
			bestDiff = diff
		}
	}

	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		diff := int(math.Abs(float64(picks[p.UserID] - winningBox)))
		if exact {
			if diff == 0 {
				winners = append(winners, p.UserID)
			}
			continue
		}
		if diff == bestDiff {
			winners = append(winners, p.UserID)
		}
	}

	summary := fmt.Sprintf("Treasure box was #%d", winningBox)
	resolution := "EXACT"
	if !exact {
		summary = fmt.Sprintf("No exact hit. Closest box to #%d wins", winningBox)
		resolution = "CLOSEST"
	}
	return winners, summary, map[string]interface{}{
		"boxes":      picks,
		"winningBox": winningBox,
		"resolution": resolution,
	}
}

func evaluateSecretBid(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	bids := make(map[string]int, len(participants))
	counts := make(map[int]int, len(participants))
	for _, p := range participants {
		bid := rand.Intn(100) + 1
		if action, ok := actions[p.UserID]; ok {
			if v, ok := asInt(action["bid"]); ok && v >= 1 && v <= 100 {
				bid = v
			}
		}
		bids[p.UserID] = bid
		counts[bid]++
	}

	winningBid := -1
	for bid, count := range counts {
		if count != 1 {
			continue
		}
		if bid > winningBid {
			winningBid = bid
		}
	}

	if winningBid < 0 {
		winners := make([]string, 0, len(participants))
		for _, p := range participants {
			winners = append(winners, p.UserID)
		}
		return winners, "No unique bid. Pot split across all players", map[string]interface{}{
			"bids": bids,
		}
	}

	winners := make([]string, 0, 1)
	for _, p := range participants {
		if bids[p.UserID] == winningBid {
			winners = append(winners, p.UserID)
			break
		}
	}
	return winners, fmt.Sprintf("Highest unique bid was %d", winningBid), map[string]interface{}{
		"bids":       bids,
		"winningBid": winningBid,
	}
}

func evaluateSpinBottle(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	picks := make(map[string]string, len(participants))
	for _, p := range participants {
		side := "LEFT"
		if action, ok := actions[p.UserID]; ok {
			if v, exists := action["side"]; exists {
				value := strings.ToUpper(strings.TrimSpace(fmt.Sprintf("%v", v)))
				if value == "LEFT" || value == "RIGHT" {
					side = value
				}
			}
		}
		picks[p.UserID] = side
	}

	stop := "LEFT"
	roll := rand.Float64()
	switch {
	case roll < 0.475:
		stop = "LEFT"
	case roll < 0.95:
		stop = "RIGHT"
	default:
		stop = "MIDDLE"
	}

	if stop == "MIDDLE" {
		return nil, "Bottle stopped in the middle. House keeps the room pot", map[string]interface{}{
			"picks":      picks,
			"bottleStop": stop,
			"noWinners":  true,
		}
	}

	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		if picks[p.UserID] == stop {
			winners = append(winners, p.UserID)
		}
	}
	return winners, fmt.Sprintf("Bottle stopped on %s", stop), map[string]interface{}{
		"picks":       picks,
		"bottleStop":  stop,
		"winningSide": stop,
	}
}

func evaluateLootBoxPool(
	participants []*roundParticipant,
	actions map[string]map[string]interface{},
) ([]string, string, map[string]interface{}) {
	const poolSize = 20
	const winnerCount = 5

	winningBoxes := make([]int, 0, winnerCount)
	numbers := rand.Perm(poolSize)
	for i := 0; i < winnerCount; i++ {
		winningBoxes = append(winningBoxes, numbers[i]+1)
	}
	sort.Ints(winningBoxes)

	boxPicks := make(map[string]int, len(participants))
	hitSet := make(map[int]struct{}, len(winningBoxes))
	for _, value := range winningBoxes {
		hitSet[value] = struct{}{}
	}

	exactWinners := make([]string, 0, len(participants))
	for _, p := range participants {
		pick := rand.Intn(poolSize) + 1
		if action, ok := actions[p.UserID]; ok {
			if v, ok := asInt(action["box"]); ok && v >= 1 && v <= poolSize {
				pick = v
			}
		}
		boxPicks[p.UserID] = pick
		if _, hit := hitSet[pick]; hit {
			exactWinners = append(exactWinners, p.UserID)
		}
	}

	if len(exactWinners) > 0 {
		return exactWinners, "Winning boxes revealed. Exact hits take the pot", map[string]interface{}{
			"boxPicks":     boxPicks,
			"winningBoxes": winningBoxes,
			"resolution":   "EXACT",
		}
	}

	bestDiff := poolSize + 1
	for _, p := range participants {
		pick := boxPicks[p.UserID]
		diff := poolSize + 1
		for _, box := range winningBoxes {
			current := int(math.Abs(float64(pick - box)))
			if current < diff {
				diff = current
			}
		}
		if diff < bestDiff {
			bestDiff = diff
		}
	}

	winners := make([]string, 0, len(participants))
	for _, p := range participants {
		pick := boxPicks[p.UserID]
		diff := poolSize + 1
		for _, box := range winningBoxes {
			current := int(math.Abs(float64(pick - box)))
			if current < diff {
				diff = current
			}
		}
		if diff == bestDiff {
			winners = append(winners, p.UserID)
		}
	}

	return winners, "No exact hit. Closest box to the winning set takes the room", map[string]interface{}{
		"boxPicks":     boxPicks,
		"winningBoxes": winningBoxes,
		"resolution":   "CLOSEST",
	}
}

func requiresAction(gameKey string) bool {
	switch gameKey {
	case "RPS_CLASH", "DICE_DUEL", "TARGET_STRIKE", "PARITY_CLASH", "COIN_TOSS", "TREASURE_BOX", "SECRET_BID", "SPIN_BOTTLE", "LOOT_BOX_POOL":
		return true
	default:
		return false
	}
}

func actionHint(gameKey string) string {
	switch gameKey {
	case "RPS_CLASH":
		return "Submit pick: ROCK, PAPER, or SCISSORS."
	case "DICE_DUEL":
		return "Predict the dice face. It rolls for 10 seconds after picks lock."
	case "TARGET_STRIKE":
		return "Submit a number between 0 and 99."
	case "PARITY_CLASH":
		return "Submit a digit between 0 and 9."
	case "COIN_TOSS":
		return "Pick HEADS or TAILS before the flip."
	case "TREASURE_BOX":
		return "Pick a treasure box from 1 to 6."
	case "SECRET_BID":
		return "Submit a hidden bid between 1 and 100. Highest unique bid wins."
	case "SPIN_BOTTLE":
		return "Choose LEFT or RIGHT before the bottle stops."
	case "LOOT_BOX_POOL":
		return "Choose one loot box from 1 to 20. Exact hits win first."
	case "HIGH_CARD":
		return "No input required. Drawing now."
	default:
		return ""
	}
}

func asInt(v interface{}) (int, bool) {
	switch t := v.(type) {
	case int:
		return t, true
	case int64:
		return int(t), true
	case float64:
		return int(math.Round(t)), true
	case float32:
		return int(math.Round(float64(t))), true
	case string:
		var out int
		if _, err := fmt.Sscanf(strings.TrimSpace(t), "%d", &out); err == nil {
			return out, true
		}
	}
	return 0, false
}

func (m *Manager) displayNameForUser(ctx context.Context, userID string) string {
	if m != nil && m.db != nil {
		if ctx == nil {
			ctx = context.Background()
		}
		filter := bson.M{"_id": strings.TrimSpace(userID)}
		if oid, err := primitive.ObjectIDFromHex(strings.TrimSpace(userID)); err == nil {
			filter = bson.M{"_id": oid}
		}

		var user bson.M
		if err := m.db.Collection("users").FindOne(ctx, filter).Decode(&user); err == nil {
			if displayName := displayNameFromUser(user); displayName != "" {
				return displayName
			}
		}
	}
	return fallbackDisplayNameForUser(userID)
}

func displayNameFromUser(user bson.M) string {
	for _, key := range []string{"fullName", "username"} {
		value, _ := user[key].(string)
		value = strings.TrimSpace(value)
		if value != "" {
			return value
		}
	}
	return ""
}

func fallbackDisplayNameForUser(userID string) string {
	uid := strings.TrimSpace(userID)
	if uid == "" {
		uid = "guest"
	}
	hash := fnv.New32a()
	_, _ = hash.Write([]byte(uid))
	value := hash.Sum32()
	adjective := guestNameAdjectives[int(value)%len(guestNameAdjectives)]
	noun := guestNameNouns[int(value/uint32(len(guestNameAdjectives)))%len(guestNameNouns)]
	number := 1000 + int(value%9000)
	return fmt.Sprintf("%s%s%d", adjective, noun, number)
}

func roundMoney(v float64) float64 {
	return math.Round(v*100) / 100
}

func cloneRoundParticipants(src map[string]*roundParticipant) map[string]*roundParticipant {
	out := make(map[string]*roundParticipant, len(src))
	for userID, participant := range src {
		if participant == nil {
			continue
		}
		cp := *participant
		out[userID] = &cp
	}
	return out
}

func participantIDs(participants []*roundParticipant) []string {
	ids := make([]string, 0, len(participants))
	for _, participant := range participants {
		if participant != nil {
			ids = append(ids, participant.UserID)
		}
	}
	return ids
}

func participantsByUserID(participants []*roundParticipant, userIDs []string) map[string]*roundParticipant {
	index := make(map[string]*roundParticipant, len(participants))
	for _, participant := range participants {
		if participant == nil {
			continue
		}
		cp := *participant
		index[participant.UserID] = &cp
	}
	out := make(map[string]*roundParticipant, len(userIDs))
	for _, userID := range userIDs {
		if participant, ok := index[userID]; ok {
			out[userID] = participant
		}
	}
	return out
}

func totalStake(participants []*roundParticipant) float64 {
	total := 0.0
	for _, participant := range participants {
		if participant != nil {
			total += participant.StakeUsd
		}
	}
	return roundMoney(total)
}

func stakeFromParticipants(participants []*roundParticipant) float64 {
	for _, participant := range participants {
		if participant != nil {
			return participant.StakeUsd
		}
	}
	return 0
}

func (m *Manager) startDiceRoll(roomCode, roundID string) {
	rollDeadline := time.Now().UTC().Add(diceRollWindow)

	m.roomsMu.Lock()
	room, ok := m.rooms[roomCode]
	if !ok || room.Round == nil || room.Round.ID != roundID {
		m.roomsMu.Unlock()
		return
	}
	round := room.Round
	if round.GameKey != "DICE_DUEL" || round.Status != "COLLECTING_ACTIONS" {
		m.roomsMu.Unlock()
		return
	}

	round.Status = "ROLLING"
	round.ActionDeadline = time.Time{}
	round.RollDeadline = rollDeadline
	room.UpdatedAt = time.Now().UTC()

	participants := cloneRoundParticipants(round.Participants)
	actions := cloneRoundActions(round.Actions)
	settledParticipants := participantsFromMap(round.SettledParticipants)
	if len(settledParticipants) == 0 {
		settledParticipants = participantsFromMap(participants)
	}
	stake := stakeFromParticipants(settledParticipants)
	pot := roundMoney(totalStake(settledParticipants))
	commission := roundMoney(pot * 0.15)
	payload := RoomRoundStartedPayload{
		RoomCode:         roomCode,
		RoundID:          round.ID,
		GameKey:          round.GameKey,
		RequiresAction:   true,
		ActionHint:       "Dice rolling. Losers drop after it stops.",
		ActionCount:      len(actions),
		PlayerCount:      len(participants),
		StakeUsd:         stake,
		PotUsd:           pot,
		CommissionUsd:    commission,
		DistributableUsd: roundMoney(pot - commission),
		Choices:          roomRoundChoices(round.GameKey, participants, actions),
		StartedAt:        round.StartedAt,
		RollDeadline:     &rollDeadline,
	}
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	m.broadcastRoomRoundStarted(memberIDs, payload)
	m.scheduleDiceRollDeadline(roomCode, roundID, rollDeadline)
}

func (m *Manager) startCoinFlip(roomCode, roundID string) {
	rollDeadline := time.Now().UTC().Add(coinFlipWindow)

	m.roomsMu.Lock()
	room, ok := m.rooms[roomCode]
	if !ok || room.Round == nil || room.Round.ID != roundID {
		m.roomsMu.Unlock()
		return
	}
	round := room.Round
	if round.GameKey != "COIN_TOSS" || round.Status != "COLLECTING_ACTIONS" {
		m.roomsMu.Unlock()
		return
	}

	round.Status = "ROLLING"
	round.ActionDeadline = time.Time{}
	round.RollDeadline = rollDeadline
	room.UpdatedAt = time.Now().UTC()

	participants := cloneRoundParticipants(round.Participants)
	actions := cloneRoundActions(round.Actions)
	stake := stakeFromParticipants(participantsFromMap(participants))
	pot := roundMoney(totalStake(participantsFromMap(participants)))
	commission := roundMoney(pot * 0.15)
	payload := RoomRoundStartedPayload{
		RoomCode:         roomCode,
		RoundID:          round.ID,
		GameKey:          round.GameKey,
		RequiresAction:   true,
		ActionHint:       "Coin flipping. Matching picks win after it lands.",
		ActionCount:      len(actions),
		PlayerCount:      len(participants),
		StakeUsd:         stake,
		PotUsd:           pot,
		CommissionUsd:    commission,
		DistributableUsd: roundMoney(pot - commission),
		Choices:          roomRoundChoices(round.GameKey, participants, actions),
		StartedAt:        round.StartedAt,
		RollDeadline:     &rollDeadline,
	}
	memberIDs := room.memberIDs()
	m.roomsMu.Unlock()

	m.broadcastRoomRoundStarted(memberIDs, payload)
	m.scheduleCoinFlipDeadline(roomCode, roundID, rollDeadline)
}

func cloneRoundActions(src map[string]map[string]interface{}) map[string]map[string]interface{} {
	out := make(map[string]map[string]interface{}, len(src))
	for userID, action := range src {
		dup := make(map[string]interface{}, len(action))
		for key, value := range action {
			dup[key] = value
		}
		out[userID] = dup
	}
	return out
}

func participantsFromMap(src map[string]*roundParticipant) []*roundParticipant {
	out := make([]*roundParticipant, 0, len(src))
	for _, participant := range src {
		if participant == nil {
			continue
		}
		cp := *participant
		out = append(out, &cp)
	}
	return out
}

func (m *Manager) scheduleDicePickDeadline(roomCode, roundID string, deadline time.Time) {
	if deadline.IsZero() {
		return
	}
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	time.AfterFunc(delay, func() {
		m.startDiceRoll(roomCode, roundID)
	})
}

func (m *Manager) scheduleDiceRollDeadline(roomCode, roundID string, deadline time.Time) {
	if deadline.IsZero() {
		return
	}
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	time.AfterFunc(delay, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_, _ = m.ResolveRoomRound(ctx, roomCode, roundID)
	})
}

func (m *Manager) scheduleCoinFlipDeadline(roomCode, roundID string, deadline time.Time) {
	if deadline.IsZero() {
		return
	}
	delay := time.Until(deadline)
	if delay < 0 {
		delay = 0
	}
	time.AfterFunc(delay, func() {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		_, _ = m.ResolveRoomRound(ctx, roomCode, roundID)
	})
}

func withoutUser(list []string, userID string) []string {
	out := make([]string, 0, len(list))
	for _, item := range list {
		if item != userID {
			out = append(out, item)
		}
	}
	return out
}

func (m *Manager) nextRoomCode() string {
	const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	for i := 0; i < 20; i++ {
		buf := make([]byte, 6)
		for j := range buf {
			buf[j] = chars[rand.Intn(len(chars))]
		}
		code := string(buf)
		if _, exists := m.rooms[code]; !exists {
			return code
		}
	}
	return strings.ToUpper(uuid.NewString()[:6])
}

func (room *multiplayerRoom) snapshot() RoomStateSnapshot {
	players := make([]RoomPlayerSnapshot, 0, len(room.PlayerOrder))
	for _, uid := range room.PlayerOrder {
		p := room.Players[uid]
		if p == nil {
			continue
		}
		players = append(players, RoomPlayerSnapshot{
			UserID:      p.UserID,
			DisplayName: p.DisplayName,
			Ready:       p.Ready,
			JoinedAt:    p.JoinedAt,
		})
	}
	return RoomStateSnapshot{
		RoomCode:   room.Code,
		GameKey:    room.GameKey,
		Visibility: room.Visibility,
		HostUserID: room.HostUserID,
		MinPlayers: room.MinPlayers,
		MaxPlayers: room.MaxPlayers,
		StakeUsd:   room.StakeUsd,
		State:      room.State,
		Players:    players,
		CreatedAt:  room.CreatedAt,
		UpdatedAt:  room.UpdatedAt,
	}
}

func (room *multiplayerRoom) memberIDs() []string {
	ids := make([]string, 0, len(room.PlayerOrder))
	for _, uid := range room.PlayerOrder {
		if _, ok := room.Players[uid]; ok {
			ids = append(ids, uid)
		}
	}
	return ids
}

func (m *Manager) broadcastRoomState(userIDs []string, snapshot RoomStateSnapshot) {
	payload := map[string]interface{}{
		"type":    "ROOM_STATE",
		"payload": snapshot,
	}
	for _, uid := range userIDs {
		m.broadcast(uid, payload)
	}
}

func (m *Manager) broadcastRoomRoundStarted(userIDs []string, payload RoomRoundStartedPayload) {
	message := map[string]interface{}{
		"type":    "ROOM_ROUND_STARTED",
		"payload": payload,
	}
	for _, uid := range userIDs {
		m.broadcast(uid, message)
	}
}

func (m *Manager) broadcastRoomRoundResult(userIDs []string, payload RoomRoundResultPayload) {
	message := map[string]interface{}{
		"type":    "ROOM_ROUND_RESULT",
		"payload": payload,
	}
	for _, uid := range userIDs {
		m.broadcast(uid, message)
	}
}
