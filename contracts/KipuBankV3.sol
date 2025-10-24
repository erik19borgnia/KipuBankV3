//SPDX-License-Identifier: MIT 

pragma solidity 0.8.30;


/*///////////////////////
        Imports
///////////////////////*/
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
/*///////////////////////
        Libraries
///////////////////////*/
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/*///////////////////////
        Interfaces
///////////////////////*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title KipuBank V3
 * @author Erik Borgnia
 * @notice Contrato para el TP Final del Módulo 4 del curso de EthKipu
 * @notice Es una simulación de banco con depósitos y extracciones, auditable por el dueño del contrato, que además incorpora USDC al que se hizo previamente
 */
contract KipuBankV3 is Ownable{
    /*///////////////////////
    DECLARACIÓN DE TIPOS
    ///////////////////////*/
    using SafeERC20 for IERC20;

    /*///////////////////////
    Variables
    ///////////////////////*/
    ///@notice variable constante para almacenar el latido (heartbeat) del Data Feed
    uint16 constant ORACLE_HEARTBEAT = 3600;
    ///@notice variable constante para almacenar el factor de decimales
    uint256 constant DECIMAL_FACTOR = 1 * 10 ** 20;

    ///@notice variable para almacenar la dirección del Chainlink Feed
    AggregatorV3Interface public s_feeds;
    //0x694AA1769357215DE4FAC081bf1f309aDC325306 Ethereum ETH/USD

    ////////////////////
    //MAPPINGS DE TODO//
    ////////////////////
    ///@notice Mapping que mantienen el balance de tokens ERC20 de las distintas cuentas 
    mapping (address user => mapping (address token => uint256 amount)) s_balances;
    ///@notice Mapping que mantienen la cantidad de depósitos de tokens ERC20 de las distintas cuentas
    mapping (address user => mapping (address token => uint32 counter)) s_deposits;
    ///@notice Mapping que mantienen la cantidad de extracciones de tokens ERC20  de las distintas cuentas
    mapping (address user => mapping (address token => uint32 amount)) s_withdrawals;
    
    ///@notice Límite de balance por cuenta
    uint128 public immutable s_bankCap;
    ///@notice Límite de extracción por cuenta
    uint128 public immutable s_withdrawLimit = 10**18; //1.000.000.000.000.000.000
    // Que sean a lo mucho la mitad de lo máximo que podría tener el contrato es bastante razonable.
    //1 trillón (o 1 quintillions) necesita menos de 128 bits, pero por coherencia se lo deja uint128
    //Acomodado a un número más razonable. Es equivalente a 1 ETH.

    ///@notice Evento emitido al depositar exitosamente
    event Deposited(address from, uint amount);
    ///@notice Evento emitido al extraer exitosamente
    event Extracted(address to, uint amount);
    ///@notice Evento emitido al depositar USDC exitosamente
    event ERC20Deposited(address from, address tokenAddress, uint amount);
    ///@notice Evento emitido al extraer USDC exitosamente
    event ERC20Extracted(address to, address tokenAddress, uint amount);
    ///@notice Evento emitido al extraer USDC exitosamente
    event ChainlinkFeedUpdated(AggregatorV3Interface oldFeed, AggregatorV3Interface newFeed);

    ///@notice Error emitido cuando se intenta depositar una cantidad inválida (=0, o la cuenta superaría el bankCap)
    error DepositNotAllowed(address to, uint amount);
    ///@notice Error emitido cuando se intenta extraer una cantidad inválda (<=0, >saldo, >límite)
    error ExtractionNotAllowed(address to, uint amount);
    ///@notice Error emitido cuando falla una extracción
    error ExtractionReverted(address to, uint amount, bytes errorData);
    ///@notice Error emitido cuando se intenta depositar una cantidad inválida de un token ERC20 (=0)
    error ERC20DepositNotAllowed(address to, address tokenAddress, uint amount);
    ///@notice Error emitido cuando se intenta extraer una cantidad inválda de un token ERC20 (<=0, >saldo)
    error ERC20ExtractionNotAllowed(address to, address tokenAddress, uint amount);
    ///@notice Error emitido cuando falla el oráculo
    error OracleCompromised();
    ///@notice Error emitido cuando la última actualización del oráculo supera el heartbeat
    error StalePrice();

    /*
        *@notice Constructor que recibe el bankCap como parámetro
        *@param _bankCap es el máximo que podría tener el contrato en total
    */
    constructor(uint128 _banckCap, address _feed) Ownable(msg.sender) {
        s_bankCap = _banckCap;
        s_feeds = AggregatorV3Interface(_feed);
    }

    /**
        *@notice Función receive para manejar depósitos directos
		*@notice Esto garantiza la consistencia con las interacciones del contrato
    */
    receive() external payable {
        depositEth();
    }

    /**
        *@notice Función para hacer un depósito
		*@notice Sólo se puede depositar un valor mayor a 0, siempre que no se supere el bankCap
    */
    function depositEth() public payable {
        require(msg.value > 0, DepositNotAllowed(msg.sender,msg.value));
        require(msg.value+s_balances[msg.sender][address(0)] <= s_bankCap, DepositNotAllowed(msg.sender,msg.value));

        s_balances[msg.sender][address(0)] += msg.value;
        s_deposits[msg.sender][address(0)]++;
        
        emit Deposited(msg.sender, msg.value);
    }

    /**
         *@notice Función externa para recibir depósitos de tokens ERC20
         *@notice Emite un evento cuando la transacción es exitosa.
         *@param _tokenAddress La dirección del contrato del token a depositar
         *@param _amount La cantidad a depositar de USDC
     */
    function depositERC20(address _tokenAddress, uint256 _amount) external {
        require(_amount > 0, DepositNotAllowed(msg.sender,_amount));
        s_balances[msg.sender][_tokenAddress] += _amount;
        s_deposits[msg.sender][_tokenAddress]++;

        emit ERC20Deposited(msg.sender, _tokenAddress, _amount);

        IERC20(_tokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
    }

    /**
        *@notice Función pública para ver el balance de ETH que uno mismo tiene
    */
    function getBalance() external view returns(uint balance_) {
        balance_ = s_balances[msg.sender][address(0)];
    }
    /**
        *@notice Función pública para ver el balance de ETH que uno mismo tiene en USD
    */
    function getBalanceInUSD() external view returns(uint balance_) {
        balance_ = convertEthInUSD(s_balances[msg.sender][address(0)]);
    }
    /**
        *@notice Función pública para ver la cantidad de depósitos de ETH que uno hizo
    */
    function getDeposits() external view returns(uint deposits_) {
        deposits_ = s_deposits[msg.sender][address(0)];
    }
    /**
        *@notice Función pública para ver la cantidad de extracciones de ETH que uno hizo
    */
    function getWithdrawals() external view returns(uint withdrawals_) {
        withdrawals_ = s_withdrawals[msg.sender][address(0)];
    }
    /**
        *@notice Función pública para ver el balance que uno mismo tiene de un token ERC20 específico
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Balance(address _tokenAddress) external view returns(uint balance_) {
        balance_ = s_balances[msg.sender][_tokenAddress];
    }
    /**
        *@notice Función pública para ver la cantidad de depósitos que uno hizo de un token ERC20 específico
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Deposits(address _tokenAddress) external view returns(uint deposits_) {
        deposits_ = s_deposits[msg.sender][_tokenAddress];
    }
    /**
        *@notice Función pública para ver la cantidad de extracciones que uno hizo de un token ERC20 específico
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Withdrawals(address _tokenAddress) external view returns(uint withdrawals_) {
        withdrawals_ = s_withdrawals[msg.sender][_tokenAddress];
    }
    /////////////////////////////
    //FUNCIONES ADMINISTRATIVAS//
    /////////////////////////////
    /**
        *@notice Función onlyOwner para ver el balance de ETH que algún usuario tiene
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
    */
    function getBalance(address user_) external onlyOwner view returns(uint balance_) {
        balance_ = s_balances[user_][address(0)];
    }/**
        *@notice Función onlyOwner para ver el balance de ETH que algún usuario tiene en USD
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
    */
    function getBalanceInUSD(address user_) external view returns(uint balance_) {
        balance_ = convertEthInUSD(s_balances[user_][address(0)]);
    }
    /**
        *@notice Función onlyOwner para ver la cantidad de depósitos de ETH que algún usuario hizo
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
    */
    function getDeposits(address user_) external onlyOwner view returns(uint deposits_) {
        deposits_ = s_deposits[user_][address(0)];
    }
    /**
        *@notice Función onlyOwner para ver la cantidad de extracciones de ETH que algún usuario hizo
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
    */
    function getWithdrawals(address user_) external onlyOwner view returns(uint withdrawals_) {
        withdrawals_ = s_withdrawals[user_][address(0)];
    }
    /**
        *@notice Función onlyOwner para ver el balance que algún usuario tiene en algún token ERC20
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Balance(address user_, address _tokenAddress) external onlyOwner view returns(uint balance_) {
        balance_ = s_balances[user_][_tokenAddress];
    }
    /**
        *@notice Función onlyOwner para ver la cantidad de depósitos que algún usuario hizo de algún token ERC20
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Deposits(address user_, address _tokenAddress) external onlyOwner view returns(uint deposits_) {
        deposits_ = s_deposits[user_][_tokenAddress];
    }
    /**
        *@notice Función onlyOwner para ver la cantidad de extracciones que algún usuario hizo de algún token ERC20
		*@dev Esta función garantiza que toda la información es auditable
        *@param user_ Usuario que se quiere auditar
        *@param _tokenAddress La dirección del contrato del token a consultar
    */
    function getERC20Withdrawals(address user_, address _tokenAddress) external onlyOwner view returns(uint withdrawals_) {
        withdrawals_ = s_withdrawals[user_][_tokenAddress];
    }
    

    /**
        *@notice Función para actualizar el Chainlink Price Feed
        *@param _feed La nueva dirección del Price Feed
        *@dev Sólo puede ser llamada por el propietario
    */
    function setFeeds(address _feed) external onlyOwner {

        emit ChainlinkFeedUpdated(s_feeds, AggregatorV3Interface(_feed));

        s_feeds = AggregatorV3Interface(_feed);

    }

    /**
        *@notice Función para hacer un depósito
		*@dev Sólo se puede depositar un valor mayor a 0, siempre que no se supere el bankCap
        *@param _amount Cantidad que se quiere extraer. Debe ser <= al balance y al límite de extracción
    */
    function withdrawEth(uint _amount) public {
        require(_amount > 0, ExtractionNotAllowed(msg.sender, _amount));
        require(_amount <= s_balances[msg.sender][address(0)], ExtractionNotAllowed(msg.sender, _amount));
        require(_amount <= s_withdrawLimit, ExtractionNotAllowed(msg.sender, _amount));

        s_balances[msg.sender][address(0)] -= _amount;
        s_withdrawals[msg.sender][address(0)]++;
        
        transferEth(_amount);
        
        emit Extracted(msg.sender, _amount);        
    }

    /**
        *@notice Función para hacer un depósito
		*@dev Sólo se puede depositar un valor mayor a 0, siempre que no se supere el bankCap
        *@param _tokenAddress La dirección del contrato del token a extraer
        *@param _amount Cantidad que se quiere extraer. Debe ser <= al balance y al límite de extracción
    */
    function withdrawERC20(address _tokenAddress, uint _amount) public {
        require(_amount > 0, ERC20ExtractionNotAllowed(msg.sender, _tokenAddress, _amount));
        require(_amount <= s_balances[msg.sender][_tokenAddress], ERC20ExtractionNotAllowed(msg.sender, _tokenAddress, _amount));

        s_balances[msg.sender][_tokenAddress] -= _amount;
        s_withdrawals[msg.sender][_tokenAddress]++;
        
        transferERC20(_tokenAddress, _amount);
        
        emit ERC20Extracted(msg.sender, _tokenAddress, _amount);        
    }

    /**
        *@notice Función interna para realizar la conversión de decimales de ETH a USD
        *@param _ethAmount La cantidad de ETH a ser convertida
        *@return convertedAmount_ El resultado del cálculo.
    */
    function convertEthInUSD(uint256 _ethAmount) internal view returns (uint256 convertedAmount_) {
        convertedAmount_ = (_ethAmount * chainlinkFeed()) / DECIMAL_FACTOR;
    }

    /**
        *@notice Función para consultar el precio en USD del ETH
        *@return ethUSDPrice_ El precio provisto por el oráculo.
    */
    function chainlinkFeed() internal view returns (uint256 ethUSDPrice_) {
        (, int256 ethUSDPrice,, uint256 updatedAt,) = s_feeds.latestRoundData();

        require(ethUSDPrice != 0, OracleCompromised());
        require((block.timestamp - updatedAt) > ORACLE_HEARTBEAT, StalePrice());

        ethUSDPrice_ = uint256(ethUSDPrice);
    }

    /**
        *@notice Función privada que transfiere la cantidad pedida por la extracción
		*@dev Nadie puede acceder a esta función excepto ESTE contrato
        *@param _amount Cantidad a transferir
    */
    function transferEth(uint _amount) private {
        (bool success, bytes memory errorData) = msg.sender.call{value: _amount}("");
        require(success, ExtractionReverted(msg.sender,_amount,errorData));
    }

    /**
        *@notice Función privada que transfiere la cantidad pedida por la extracción
		*@dev Nadie puede acceder a esta función excepto ESTE contrato
        *@param _tokenAddress La dirección del contrato del token a transferir
        *@param _amount Cantidad a transferir
    */
    function transferERC20(address _tokenAddress, uint _amount) private {
        IERC20(_tokenAddress).safeTransferFrom(address(this), msg.sender, _amount);
    }




}