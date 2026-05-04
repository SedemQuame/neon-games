package session

import (
	"context"
	"testing"
)

func TestCreateRoomAllowsMultipleRoomsForSameGame(t *testing.T) {
	manager := NewManager(nil, nil, nil, nil)
	req := CreateRoomRequest{
		GameKey:    "RPS_CLASH",
		Visibility: roomVisibilityPublic,
		MinPlayers: 2,
		MaxPlayers: 4,
		StakeUsd:   1,
	}

	first, err := manager.CreateRoom(context.Background(), "host-one", req)
	if err != nil {
		t.Fatalf("create first room: %v", err)
	}
	second, err := manager.CreateRoom(context.Background(), "host-two", req)
	if err != nil {
		t.Fatalf("create second room: %v", err)
	}
	if first.RoomCode == second.RoomCode {
		t.Fatalf("expected distinct room codes, got %s", first.RoomCode)
	}

	rooms := manager.ListPublicRooms(ListPublicRoomsRequest{GameKey: "RPS_CLASH"})
	if len(rooms) != 2 {
		t.Fatalf("expected two public rooms for the same game, got %d", len(rooms))
	}
}

func TestCreateRoomStartsHostUnready(t *testing.T) {
	manager := NewManager(nil, nil, nil, nil)
	room, err := manager.CreateRoom(context.Background(), "host", CreateRoomRequest{
		GameKey:    "RPS_CLASH",
		Visibility: roomVisibilityPublic,
		MinPlayers: 2,
		MaxPlayers: 4,
		StakeUsd:   1,
	})
	if err != nil {
		t.Fatalf("create room: %v", err)
	}
	if len(room.Players) != 1 {
		t.Fatalf("expected one host player, got %d", len(room.Players))
	}
	if room.Players[0].Ready {
		t.Fatal("expected room host to start unready")
	}
}

func TestCreateRoomMovesCreatorToFreshRoom(t *testing.T) {
	manager := NewManager(nil, nil, nil, nil)
	req := CreateRoomRequest{
		GameKey:    "RPS_CLASH",
		Visibility: roomVisibilityPublic,
		MinPlayers: 2,
		MaxPlayers: 4,
		StakeUsd:   1,
	}

	original, err := manager.CreateRoom(context.Background(), "host", req)
	if err != nil {
		t.Fatalf("create original room: %v", err)
	}
	if _, err := manager.JoinRoom(context.Background(), "guest", JoinRoomRequest{RoomCode: original.RoomCode}); err != nil {
		t.Fatalf("join original room: %v", err)
	}

	fresh, err := manager.CreateRoom(context.Background(), "host", req)
	if err != nil {
		t.Fatalf("create fresh room: %v", err)
	}
	if fresh.RoomCode == original.RoomCode {
		t.Fatalf("expected a fresh room code, got %s", fresh.RoomCode)
	}

	hostRoom, ok := manager.GetUserRoomSnapshot("host")
	if !ok || hostRoom.RoomCode != fresh.RoomCode {
		t.Fatalf("expected host in fresh room, got %#v", hostRoom)
	}
	guestRoom, ok := manager.GetUserRoomSnapshot("guest")
	if !ok || guestRoom.RoomCode != original.RoomCode {
		t.Fatalf("expected guest to stay in original room, got %#v", guestRoom)
	}
	if guestRoom.HostUserID != "guest" {
		t.Fatalf("expected original room host to transfer to guest, got %s", guestRoom.HostUserID)
	}
}

func TestJoinRoomMovesUserBetweenWaitingRooms(t *testing.T) {
	manager := NewManager(nil, nil, nil, nil)
	req := CreateRoomRequest{
		GameKey:    "RPS_CLASH",
		Visibility: roomVisibilityPublic,
		MinPlayers: 2,
		MaxPlayers: 4,
		StakeUsd:   1,
	}

	first, err := manager.CreateRoom(context.Background(), "first-host", req)
	if err != nil {
		t.Fatalf("create first room: %v", err)
	}
	second, err := manager.CreateRoom(context.Background(), "second-host", req)
	if err != nil {
		t.Fatalf("create second room: %v", err)
	}
	if _, err := manager.JoinRoom(context.Background(), "guest", JoinRoomRequest{RoomCode: first.RoomCode}); err != nil {
		t.Fatalf("join first room: %v", err)
	}

	joined, err := manager.JoinRoom(context.Background(), "guest", JoinRoomRequest{RoomCode: second.RoomCode})
	if err != nil {
		t.Fatalf("join second room: %v", err)
	}
	if joined.RoomCode != second.RoomCode {
		t.Fatalf("expected guest in second room, got %s", joined.RoomCode)
	}

	firstSnapshot, ok := manager.GetUserRoomSnapshot("first-host")
	if !ok || firstSnapshot.RoomCode != first.RoomCode {
		t.Fatalf("expected first room to remain, got %#v", firstSnapshot)
	}
	for _, player := range firstSnapshot.Players {
		if player.UserID == "guest" {
			t.Fatal("expected guest to be removed from first room")
		}
	}
}
