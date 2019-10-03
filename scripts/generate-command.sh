#!/bin/bash

# Create command Folder with files
mkdir command
touch command/main.go

cat <<EOM > command/main.go
package main

import (
	"flag"
	gowsh "go-wsh"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"sync"
	"time"

	"github.com/gorilla/mux"
	"github.com/gorilla/websocket"
)

type runtime struct {
	wg *sync.WaitGroup
	http.Server
}

func newRuntime() *runtime {
	return &runtime{
		wg: &sync.WaitGroup{},
	}
}

func (rt *runtime) loadConfiguration() {
	log.Println("[INFO] Loading Configurations")
	rt.Addr = "localhost:8080"
	rt.WriteTimeout = time.Second * 15
	rt.ReadTimeout = time.Second * 15
	rt.IdleTimeout = time.Second * 60
}

func (rt *runtime) serveHTTP(routerHandles *mux.Router) {
	defer rt.wg.Done()
	rt.Handler = routerHandles
	log.Printf("[INFO] HTTP server started at \"%s\"\n", rt.Addr)
	log.Fatal(rt.ListenAndServe())
}

var (
	hub *gowsh.EventHub
)

func main() {
	log.Println("[INFO] Starting API")
	rt := newRuntime()
	rt.loadConfiguration()
	rt.wg.Add(1)
	log.Println("[INFO] Starting HTTP server")
	go rt.serveHTTP(router())
	log.Println("[INFO] Starting Websocket Hub")
	hub = gowsh.NewEventHub()
	hub.AddHandler("TEST_WS", testWs)
	go hub.Run()
	go testWebSocketConnection(rt.wg)
	rt.wg.Wait()
}

func testWs(message *gowsh.EventMessage) {
	message.Data = "Funciona"
	message.Client.SendMessage(message)
}

func router() *mux.Router {
	r := mux.NewRouter()
	r.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		ServeWs(hub, w, r)
	})
	r.HandleFunc("/ws/{group_id}", func(w http.ResponseWriter, r *http.Request) {
		ServeWs(hub, w, r)
	})
	return r
}

var upgrader = gowsh.Upgrader

func ServeWs(hub *gowsh.EventHub, w http.ResponseWriter, r *http.Request) {
	wsConn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		log.Printf("[ERRO] Creating websocket session: %v", err)
	}
	newClientSes := gowsh.NewClientSession()
	newClientSes.WebsocketConnection = wsConn
	newClientSes.EventsHub = hub

	groupID := mux.Vars(r)["group_id"]
	if groupID == "" {
		newClientSes.Group = addClientGroup(groupID, newClientSes, hub)
	} else {
		group, isAdded := hub.ClientGroups[groupID]
		if isAdded {
			group.AddClientSession(newClientSes)
		} else {
			addClientGroup(groupID, newClientSes, hub)
		}
		newClientSes.Group = groupID
	}

	go newClientSes.WriteToSocket()
	newClientSes.ReadFromSocket()
}

func addClientGroup(groupID string, newClientSes *gowsh.ClientSession, hub *gowsh.EventHub) string {
	newClientGroup := gowsh.NewClientGroup(groupID)
	newClientGroup.AddClientSession(newClientSes)
	hub.AddGroup(newClientGroup)
	return newClientGroup.ID
}

var addr = flag.String("addr", "localhost:8080", "http service address")

func testWebSocketConnection(wg *sync.WaitGroup) {
	defer wg.Done()
	flag.Parse()
	log.SetFlags(0)

	interrupt := make(chan os.Signal, 1)
	signal.Notify(interrupt, os.Interrupt)

	u := url.URL{Scheme: "ws", Host: *addr, Path: "/ws"}
	log.Printf("[WS CLIENT] connecting to %s", u.String())

	c, _, err := websocket.DefaultDialer.Dial(u.String(), nil)
	if err != nil {
		log.Fatal("[WS CLIENT] dial:", err)
	}
	defer c.Close()

	done := make(chan struct{})

	go func() {
		defer close(done)
		for {
			_, message, err := c.ReadMessage()
			if err != nil {
				log.Println("[WS CLIENT] read:", err)
				return
			}
			log.Printf("[WS CLIENT] recv: %s", message)
		}
	}()

	for send := 0; send < 5; send++ {
		err := c.WriteMessage(websocket.TextMessage, []byte("{\"event\": \"TEST_WS\", \"data\": \"\"}"))
		if err != nil {
			log.Println("[WS CLIENT] write:", err)
			return
		}
	}
	time.Sleep(5 * time.Second)
}


EOM