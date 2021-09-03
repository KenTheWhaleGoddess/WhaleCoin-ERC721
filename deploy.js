// Right click on the script name and hit "Run" to execute
(async () => {
    try {
        console.log('Running deployWithWeb3 script...')
        const contractName = 'Storage' // Change this for other contract
        const constructorArgs = [from: '0x1B3FEA07590E63Ce68Cb21951f3C133a35032473']    // Put constructor args (if any) here for your contract
    
        // Note that the script needs the ABI which is generated from the compilation artifact.
        // Make sure contract is compiled and artifacts are generated
        const artifactsPath = `browser/contracts/artifacts/Collectible.json` // Change this for different path

        const metadata = JSON.parse(await remix.call('fileManager', 'getFile', artifactsPath))
        const accounts = await web3.eth.getAccounts()
        console.log(metadata);
    
        let contract = new web3.eth.Contract(metadata.output.abi)
    
        contract = contract.deploy({
            data: web3.utils.asciiToHex(metadata.settings.metadata.bytecodeHash),
            arguments: constructorArgs,
            from: '0x1B3FEA07590E63Ce68Cb21951f3C133a35032473'
        })
    
        const newContractInstance = await contract.send({
            gas: 1500000,
            gasPrice: '30000000000'
        })
        console.log('Contract deployed at address: ', newContractInstance.options.address)
    } catch (e) {
        console.log(e.message)
    }
  })()
