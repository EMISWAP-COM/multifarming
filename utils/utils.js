const { BigNumber } = require("@ethersproject/bignumber");

function tokens(val) {
    return BigNumber.from(val).mul(BigNumber.from("10").pow(18)).toString();
}

function tokensDec(val, dec) {
    return BigNumber.from(val).mul(BigNumber.from("10").pow(dec)).toString();
}

async function shiftBlocks(network, shiftValue) {
    for (const iterator of [...Array(shiftValue).keys()]) {
        await network.provider.send("evm_mine");
    }
}

function timeout(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

module.exports = {
    tokens,
    tokensDec,
    shiftBlocks,
    timeout
};
