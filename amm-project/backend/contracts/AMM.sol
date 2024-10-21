// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract AMM {
    IERC20 public tokenA;
    IERC20 public tokenB;

    // Liquidez total e liquidez de cada usuário
    uint256 public totalLiquidity;
    mapping(address => uint256) public liquidity;
    mapping(address => bool) public isStaking;
    mapping(address => uint256) public accumulatedFess;

    uint256 public constant STAKER_PERCENTAGE = 100;
    uint256 public constant NON_STAKER_PERCENTAGE = 80; 

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    // Adiciona liquidez à pool
    function addLiquidity(uint256 amountA, uint256 amountB) public {
        require(tokenA.transferFrom(msg.sender, address(this), amountA), "Transfer of Token A failed.");
        require(tokenB.transferFrom(msg.sender, address(this), amountB), "Transfer of Token B failed.");

        // O currentLiquidity é a quantidade de liquidez que o usuário está adicionando ao pool
        uint256 liquidityAdded = sqrt(amountA * amountB); // Fórmula simples para calcular a liquidez
        // Adiciona a liquidez ao pool e ao usuário
        liquidity[msg.sender] += liquidityAdded;
        totalLiquidity += liquidityAdded;
    }

    function stakeLiquidity() public {
        require(liquidity[msg.sender] > 0, "You must provide liquidity first");
        require(!isStaking[msg.sender], "You are already staking");
        // Bloquear a retirada da liquidez por um período de tempo
        isStaking[msg.sender] = true;
    }

    function unstakeLiquidity() public {
        require(isStaking[msg.sender], "You are not staking");
        // Desbloquear a retirada da liquidez
        isStaking[msg.sender] = false;
    }

    function swap(address fromToken, address toToken, uint256 amount) public {
        require(fromToken != toToken, "Tokens must be different.");
        require(fromToken == address(tokenA) || fromToken == address(tokenB), "Invalid from token.");
        require(toToken == address(tokenA) || toToken == address(tokenB), "Invalid to token.");

        // Transfere o token de entrada para a pool
        require(fromToken.transferFrom(msg.sender, address(this), amount), "Transfer of from token failed.");

        // Calcula a quantidade de tokens da pool
        uint256 fromTokenReserve = fromToken.balanceOf(address(this));
        uint256 toTokenReserve = toToken.balanceOf(address(this));

        // Calcula as taxas
        uint256 amountInWithFee = (amountIn * 997) / 1000;

        // Calcula a quantidade de tokens de saída com a formula x * y = k
        uint256 amountOut = (amountInWithFee * toTokenReserve) / (fromTokenReserve + amountInWithFee);

        // transfere os tokens de saída para o usuário
        require(toToken.transfer(msg.sender, amountOut), "Transfer of to token failed.");

        uint256 fee = amountIn - amountInWithFee;

        distributeFees(fee);
    }

    // Distribuir taxas entre provedores de liquidez, ajustado para stakers e não-stakers
    function distributeFee(uint256 fee) internal {
        for (address provider : allProviders) {  // 'allProviders' é um array com todos os provedores de liquidez
            uint256 share = (liquidity[provider] * fee) / totalLiquidity;

            // Se o usuário estiver stakando, ele recebe 100% da taxa
            // Se não, ele recebe 80% da sua parte
            if (isStaking[provider]) {
                accumulatedFees[provider] += (share * STAKER_PERCENTAGE) / 100;
            } else {
                accumulatedFees[provider] += (share * NON_STAKER_PERCENTAGE) / 100;
            }
        }
    }

    // Função para os provedores de liquidez resgatarem suas taxas acumuladas
    function claimFees() public {
        uint256 fees = accumulatedFees[msg.sender];
        require(fees > 0, "No fees to claim");

        accumulatedFees[msg.sender] = 0;
        require(tokenA.transfer(msg.sender, fees), "Transfer of fees failed");
    }

    // Babylonian method usado pela UniSwap V2
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
