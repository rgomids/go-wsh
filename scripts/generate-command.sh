#!/bin/bash

# Create command Folder with files
mkdir command
touch command/main.go

cat <<EOM > command/main.go
package main

import (
	gowsh "go-wsh"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/mux"
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
	rt.wg.Add(2)
	log.Println("[INFO] Starting HTTP server")
	go rt.serveHTTP(router())
	log.Println("[INFO] Starting Websocket Hub")
	hub = gowsh.NewEventHub()
	go hub.Run()
	rt.wg.Wait()
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

EOM