package token

import (
	"os"
	"path/filepath"
	"testing"
)

func TestReadPEMFileFromRailwayStyleDirectoryMount(t *testing.T) {
	t.Parallel()

	dir := filepath.Join(t.TempDir(), "jwt_public.pem")
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatalf("mkdir: %v", err)
	}

	want := []byte("test-public-key")
	if err := os.WriteFile(filepath.Join(dir, "jwt_public.pem"), want, 0o644); err != nil {
		t.Fatalf("write file: %v", err)
	}

	got, err := readPEMFile(dir)
	if err != nil {
		t.Fatalf("readPEMFile: %v", err)
	}
	if string(got) != string(want) {
		t.Fatalf("unexpected content: got %q want %q", got, want)
	}
}
