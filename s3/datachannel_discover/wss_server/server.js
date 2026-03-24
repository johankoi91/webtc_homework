const WebSocket = require("ws")

const wss = new WebSocket.Server({port:9000})

let clients=[]

wss.on("connection",(ws)=>{

    clients.push(ws)

    ws.on("message",(msg)=>{

        for(let c of clients){

            if(c!==ws && c.readyState===WebSocket.OPEN){

                c.send(msg)

            }
        }

    })

})