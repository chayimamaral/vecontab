
#!/bin/bash

if [[ "$1" == "start" ]]; then
    # Iniciar os servidores

    # Iniciar o servidor Node.js com Yarn em segundo plano
    echo
    echo "===>Iniciando o servidor Node.js..."
    cd backend
    nohup yarn dev > node.log 2>&1 &

    # Aguardar até que o servidor Node.js esteja em execução
    echo "Aguardando resposta do servidor Node.js..."
    until $(curl --output /dev/null --silent --head --fail http://localhost:3333); do
        printf '.'
        sleep 1
    done
   echo
    echo "<===Servidor Node.js está em execução."

    # Iniciar o servidor React com Yarn em segundo plano
    echo "===>Iniciando o servidor React..."
    cd ../frontend
    nohup yarn dev > react.log 2>&1 &

    # Aguardar até que o servidor React esteja em execução
    echo "Aguardando resposta do servidor React..."
    until $(curl --output /dev/null --silent --head --fail http://localhost:3000); do
        printf '.'
        sleep 1
    done
    echo "<===Servidor React está em execução."

elif [[ "$1" == "stop" ]]; then
    # Parar os servidores

    # Parar o servidor React
    echo
    echo "==>Parando o servidor React..."
    pkill -f "yarn start"

    # Aguardar até que o servidor React seja encerrado
    echo
    echo "Aguardando encerramento do servidor React..."
    while pgrep -f "yarn start" >/dev/null; do
        sleep 1
    done
    echo "<===Servidor React foi encerrado."

    # Parar o servidor Node.js
    echo "===>Parando o servidor Node.js..."
    pkill -f "yarn server"

    # Aguardar até que o servidor Node.js seja encerrado
    echo "Aguardando encerramento do servidor Node.js..."
    while pgrep -f "yarn server" >/dev/null; do
        sleep 1
    done
    echo "<===Servidor Node.js foi encerrado."

else
    echo "Parâmetros válidos: start, stop"
    echo "Uso: ./vecontab.sh [start|stop]"
fi

