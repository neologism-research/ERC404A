import dayjs from "dayjs";
import duration from "dayjs/plugin/duration";
import { DeployFunction } from "hardhat-deploy/types";
import { HardhatRuntimeEnvironment } from "hardhat/types";
dayjs.extend(duration);

const deployFunc: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
  const { deployments, getNamedAccounts } = hre;
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  await deploy("ERC404A", {
    args: ["Azukira", "AKA"],
    from: deployer,
    log: true,
  });
};

deployFunc.tags = ["ERC404A", "dev", "uat", "prod"];

export default deployFunc;
