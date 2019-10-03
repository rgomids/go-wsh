package gowsh

import (
	"net/http"

	"github.com/gorilla/websocket"
)

var (
	// ClientGroupsLength é o tamanho dos grupos que estão no Hub
	ClientGroupsLength = 5
	Upgrader           = websocket.Upgrader{
		ReadBufferSize:  1024,
		WriteBufferSize: 1024,
		CheckOrigin:     func(r *http.Request) bool { return true },
	}
)
