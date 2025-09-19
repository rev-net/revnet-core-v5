# REVSuckerDeploymentConfig
[Git Source](https://github.com/rev-net/revnet-core-v5/blob/364afaae78a8f60af2b98252dc96af1c2e4760d3/src/structs/REVSuckerDeploymentConfig.sol)

**Notes:**
- member: deployerConfigurations The information for how to suck tokens to other chains.

- member: salt The salt to use for creating suckers so that they use the same address across chains.


```solidity
struct REVSuckerDeploymentConfig {
    JBSuckerDeployerConfig[] deployerConfigurations;
    bytes32 salt;
}
```

