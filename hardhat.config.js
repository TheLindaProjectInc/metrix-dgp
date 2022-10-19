/**
 * @type import('hardhat/config').HardhatUserConfig
 */
module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.7',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
    overrides: {
      'contracts/blockGasLimit-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/blockSize-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/budgetFee-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/gasSchedule-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/governanceCollateral-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/minGasPrice-dgp.sol': {
        version: '0.5.8',
      },
      'contracts/transactionFeeRates-dgp.sol': {
        version: '0.5.8',
      },
    },
  },
};
