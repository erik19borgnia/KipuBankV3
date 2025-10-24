# TP Final del Módulo 4 del curso de Ethereum
Este contrato es una mejora del KipuBank (TP Final del módulo 3), encontrable aquí: https://github.com/erik19borgnia/KipuBank2 \
En este proyecto se agregaron las siguientes mejoras:
 - Se agregó soporte para tokens ERC20, haciendo uso de multimappings del estilo [address user][address tokenAddress]. Para caso de transferencias de ETH se usó address(0) como tokenAddress.
 - Se agregó convertibilidad de ETH a USD para gestionar saldos de una forma más adecuada a lo que usamos normalmente. Para esto se usa un DataFeed de Chainlink, configurable POR EL OWNER.
 - Se utilizan librerías estándar de OpenZeppelin para los dos puntos anteriores. Esto permite un código más robusto y probado.
 - El límite de extracción establecido se modificó a 1'000'000'000'000'000'000 wei. (1 trillon, o 1 quintillion, que es 1 ETH)


## Despliegue

Usando Remix, copiar el repositorio y desplegar utilizando RemixVM para testear, o Injected Provider con Metamask para alguna testnet o red principal.\
Obviamente también se puede usar algún otro método de despliegue.\
**Se debe asignar un límite para el balance de una cuenta al desplegar, se recomienda que sea al menos de 1'000'000'000'000'000'000 wei. (1 trillon, o 1 quintillion, que es 1 ETH).** \
**También se debe asignar una dirección de un Feed para obtener la conversión de ETH a USD (recomendado: 0x694AA1769357215DE4FAC081bf1f309aDC325306).**

## Interacciones con el contrato

Las mismas interacciones del contrato KipuBank se mantienen, y trabajan con ETH.\
Se agregan las mismas interacciones para trabajar con tokens ERC20, los nombres son los mismos agregando ERC20 al final (por ejemplo depositERC20), y toman por parámetro la cantidad y la dirección del token con el que se va a operar (en el caso de las funciones external view que dan información, no hay parámetro cantidad).\
Por último, se agrega una función que convierte el ETH depositado en USD para conocer el valor en USD del balance. **SOLO SE TOMA EN CUENTA EL ETH DEPOSITADO, NO LOS TOKENS ERC20**
