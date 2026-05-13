import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("AlejandriaRegistryModule", (m) => {
  const registry = m.contract("AlejandriaRegistry");
  return { registry };
});
