import { BigNumber } from "@ethersproject/bignumber";
import { ethers } from "hardhat";
export const calculateAcceptablePrice = (
  marketPrice: BigNumber,
  isLong: boolean
) => {
  const oneBN = ethers.utils.parseEther("1");
  const priceImpactDecimalPct = oneBN.div(100);
  return isLong
    ? marketPrice.mul(priceImpactDecimalPct.add(oneBN)).div(oneBN)
    : marketPrice.mul(oneBN.sub(priceImpactDecimalPct)).div(oneBN);
};
