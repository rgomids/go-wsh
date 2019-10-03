package gowsh

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/gorilla/websocket"
)

// ClientGroup é responsável por manter
// as informações dos usuários do mesmo grupo
// para que possam fazer broadcast das mensagens
type ClientGroup struct {
	// O ID do grupo serve para identifica-lo em meio a outros grupos
	ID string
	// Lista com todas as sessões de clientes conectados nesse grupo
	ClientSessions []*ClientSession
}

// NewClientGroup retorna um novo grupo sem sessões
func NewClientGroup(groupID string) *ClientGroup {
	if groupID == "" {
		return &ClientGroup{
			ID: GenerateULID(),
		}
	}
	return &ClientGroup{
		ID: groupID,
	}
}

// AddClientSession coloca uma sessão nova dentro do grupo
func (cg *ClientGroup) AddClientSession(clientSession *ClientSession) {
	cg.ClientSessions = append(cg.ClientSessions, clientSession)
}

func (cg *ClientGroup) sendMessageToGroup(message *EventMessage) {
	for _, clientSession := range cg.ClientSessions {
		clientSession.SendMessage(message)
	}
}

// ClientSession é responsável por manter as
// informações do usuário que fez a solicitação
type ClientSession struct {
	// ID serve para diferencia-lo dos outros dãã...
	ID string
	// Esse é o grupo que esse client está inserido
	Group string
	// WebsocketConnection carrega a conexão WS do cliente para que ele possa continuar se comunicando
	WebsocketConnection *websocket.Conn
	// SendResponse envia para o usuário as respostas das chamadas
	SendResponse chan []byte
	// FinishClientSession finaliza o hub de operação dele
	FinishClientSession chan bool
	// Este cara vai receber a solicitação e vai trata-la
	EventsHub *EventHub
}

// NewClientSession cria uum novo usuário
func NewClientSession() *ClientSession {
	return &ClientSession{
		ID:                  GenerateULID(),
		SendResponse:        make(chan []byte),
		FinishClientSession: make(chan bool),
	}
}

// SendMessage envia uma mensagem no padrão EventMessage para o Client
func (cs *ClientSession) SendMessage(message *EventMessage) {
	msg, err := json.Marshal(message)
	if err != nil {
		log.Printf("[ERRO] SendMessage can't marshal message: %v", err)
		return
	}
	cs.SendResponse <- msg
}

// SendBroadcast envia uma mensagem no padrão EventMessage para todos os Clients do mesmo grupo
func (cs *ClientSession) SendBroadcast(message *EventMessage) {
	cs.EventsHub.ClientGroups[cs.Group].sendMessageToGroup(message)
}

// ReadFromSocket Pega as mensagens que vem do websocket
func (cs *ClientSession) ReadFromSocket() {
	eventMessageRaw := &EventMessage{}
	for {
		err := cs.WebsocketConnection.ReadJSON(eventMessageRaw)
		if err != nil {
			log.Printf("[ERRO] ReadFromSocket can't read message: %v\n", err)
		}
		cs.SendResponse <- []byte(fmt.Sprintf(`{"event": "%s_PROCESSING"}`, eventMessageRaw.Event))
		go log.Printf("[WS] New Event: %s\n", eventMessageRaw.Event)
		eventMessageRaw.Client = cs
		cs.EventsHub.Messaging <- eventMessageRaw
	}
}

// WriteToSocket Envia a mensagem para o cliente
func (cs *ClientSession) WriteToSocket() {
	defer func() {
		close(cs.SendResponse)
		close(cs.FinishClientSession)
	}()
	for {
		select {
		case message, isOk := <-cs.SendResponse:
			if !isOk {
				log.Printf("[ERRO] WriteToSocket can't get message: %+v", cs.ID)
			}
			// Nessa parte deve ser utilizado a conexão
			cs.WebsocketConnection.WriteMessage(websocket.TextMessage, message)
		// Aqui a sessão do cliente é fechada
		case <-cs.FinishClientSession:
			return
		}
	}
}
