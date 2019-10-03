package gowsh

// EventMessage é o modelo de
// mensagens que serão compartilhados no webscoket
type EventMessage struct {
	// Event é o tipo de evento que está relacionado a essa chamada
	Event string `json:"event"`

	// Data é a informação que a mensagem está transportando
	Data interface{} `json:"data"`

	// Client é o usuário que fez a solicitação
	Client *ClientSession `json:"-"`
}

// EventHub é o centralizador das mensagens,
// ele é responsável por pegar as mensagens e as enviar
// para as rotas
type EventHub struct {
	// Este é o canal que vai distribuir as mensagens
	Messaging chan *EventMessage
	// Este canal finaliza o hub
	Finish chan bool
	// Essa é a lista com todos os Handlers
	Handlers *EventHandlers
	// Armazena todos os grupos de mensagem
	ClientGroups map[string]*ClientGroup
}

// AddGroup update group list with one new group
func (eh *EventHub) AddGroup(clientGroup *ClientGroup) {
	eh.ClientGroups[clientGroup.ID] = clientGroup
}

// EventHandlers carrega a lista com todas as possiveis
// chamadas e seus handlers
type EventHandlers struct {
	HandlerList map[string]func(*EventMessage)
}

// NewEventHub cria o novo EventHub com o channel já iniciado
func NewEventHub() *EventHub {
	return &EventHub{
		Messaging: make(chan *EventMessage),
		Finish:    make(chan bool),
		Handlers: &EventHandlers{
			HandlerList: make(map[string]func(*EventMessage)),
		},
		ClientGroups: make(map[string]*ClientGroup, ClientGroupsLength),
	}
}

// AddHandler adiciona um novo handler para as chamadas
func (eh *EventHub) AddHandler(event string, f func(*EventMessage)) {
	eh.Handlers.HandlerList[event] = f
}

// Run aqui é o hub onde as mensagens vão ser lidas do messaging
// e posteriormente serem enviadas
func (eh *EventHub) Run() {
	defer func() {
		close(eh.Messaging)
		close(eh.Finish)
	}()
	for {
		select {
		// Sempre que uma mensagem for recebida ela deve ser enviada aqté este lugar
		case message := <-eh.Messaging:
			// Aqui devem ficar as verificações sobre quais eventos estão sendo enviados, pois assim podemos direcionar para cada handler'
			go EventDispatcher(eh.Handlers, message)
		// Se receber algo nesse canal o hub é finalizado
		// Essa chamada deve ser feita apenas em casos especificos pois
		// assim que o hub for fechado a aplicação é encerrada
		case <-eh.Finish:
			return
		}
	}
}

// EventDispatcher é o responsável por tratar as mensagens recebidas
// pelo websocket e direcionalas ao handler correto
//
// Essa função poderia estar um um arquivo próprio dentro deste pacote, pois a mesma vai acabar ficando muito grande
func EventDispatcher(handlers *EventHandlers, message *EventMessage) {
	if f, ok := handlers.HandlerList[message.Event]; ok {
		f(message)
	} else {
		message.Client.SendMessage(&EventMessage{Event: "EVENT_NOT_FOUND"})
	}
}
