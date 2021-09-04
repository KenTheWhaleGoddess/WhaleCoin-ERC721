//"SPDX-License-Identifier: UNLICENSED"
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract SimpleCollectible is ERC721, Ownable {
    uint256 private tokenCounter;

    uint256 private _presalePrice = 10000000000000000; //.01 ETH
    uint256 private _salePrice = 50000000000000000; // .05 ETH

    uint256 private _maxPerTx = 11; // Set to one higher than actual, to save gas on <= checks.

    uint256 public _presaleSupply = 3;
    uint256 public _totalSupply = 9; 

    string private _baseTokenURI;
    uint private _saleState; // 0 - No sale. 1 - Presale. 2 - Main Sale.

    // Faciliating the needed functionality for the presale
    mapping(address => bool) addressToPreSaleEntry;

    constructor () ERC721 ("WhaleCoin","WHALE")  {
        tokenCounter = 0;
        _saleState = 0;
    }

    function mintPresaleCollectibles(uint256 _count) public payable {
        require(isPresaleOpen(), "Presale is not yet open. See wenPresale and wenSale for more info");
        require(!isPresaleComplete(), "Presale is over. See wenSale for more info");

        require(_count < _maxPerTx, "Cant mint more than _maxPerTx");
        require(isWalletInPresale(msg.sender), "Wallet isnt in presale! The owner needs to addWalletToPresale.");
        require((_count + tokenCounter) <= _presaleSupply, "Ran out of NFTs for presale! Sry!");
        require(msg.value >= (_presalePrice * _count), "Ether value sent is too low");

        createCollectibles(_count);
    }

    function mintCollectibles(uint256 _count) public payable {
        require(isSaleOpen(), "Sale is not yet open");
        require(isPresaleComplete(), "Presale has not started or is ongoing");
        require(_count < _maxPerTx, "Cant mint more than mintMax");
        require((_count + tokenCounter) <= _totalSupply, "Ran out of NFTs for sale! Sry!");
        require(msg.value >= (_salePrice * _count), "Ether value sent is not correct");

        createCollectibles(_count);
    }

    function createCollectibles(uint256 _count) private {
        for(uint i = 0; i < _count; i++) {
            createCollectible();
        }
    }

    function createCollectible() private {
            _safeMint(msg.sender, tokenCounter);
            tokenCounter = tokenCounter + 1;
    }

    function tokensMinted() public view returns (uint256) {
        return tokenCounter;
    }
    
    function saleInstructionsForNoobs() public view returns (string memory) {
        if (isSaleOpen() && !isSaleComplete()) {
            return "Sale is currently ongoing. \nEveryone is eligible for main sale.\nWhen calling the mint function, input ETH equal to the sale price .05 ETH * n (Number of NFTs).";
        } else if (isSaleComplete()){
            return "Sale is complete. Please find us on OpenSea or other.";
        } else {
            return "Sale has not started. \n wenSale will say now! when sale is active.";
        }
    }
    
    function presaleInstructionsForNoobs() public view returns (string memory) {
        if (isPresaleOpen() && !isPresaleComplete()) {
            return "Presale is currently ongoing. \nCheck if your wallet is eligible for presale using isWalletInPresale.\nWhen calling the mint function, input ETH equal to the presale price .01 ETH * n (Number of NFTs).";
        } else if (isPresaleComplete()){
            return "Presale is complete. Head to the function saleInstructionsForNoobs for Main Sale instructions.";
        } else {
            return "Presale has not started. \nCheck if your wallet is eligible for presale using isWalletInPresale.\nwenPresale will say now! when presale is active.";
        }
    }
    
    function minted() public view returns (uint256) {
        return tokenCounter;
    }

    function wenPresale() public view returns (string memory) {
        if(!isPresaleOpen()) return "#soon";
        return isPresaleComplete() ? "complete" : "now!";
    }

    function wenSale() public view returns (string memory) {
        if(!isSaleOpen()) return "#soon";
        return isSaleComplete() ? "complete" : "now!";
    }

    function isSaleOpen() public view returns (bool) {
        return _saleState == 2;
    }

    function isSaleComplete() public view returns (bool) {
        return tokenCounter == _totalSupply;
    }
    function isPresaleOpen() public view returns (bool) {
        return _saleState >= 1;
    }
    function isPresaleComplete() public view returns (bool) {
        return tokenCounter >= _presaleSupply;
    }
    
    function getSaleState() private view returns (uint){
        return _saleState;
    }
    
    function setSaleState(uint saleState) public onlyOwner {
        _saleState = saleState;
    }
    
    function getSalePrice() private view returns (uint){
        return _salePrice;
    }
    
    function setSalePrice(uint salePrice) public onlyOwner {
        _salePrice = salePrice;
    }
    function getPresalePrice() private view returns (uint){
        return _presalePrice;
    }
    
    function setPresalePrice(uint presalePrice) public onlyOwner {
        _presalePrice = presalePrice;
    }

    function isWalletInPresale(address _address) public view returns (bool) {
        return addressToPreSaleEntry[_address];
    }
    function addWalletToPreSale(address _address) public onlyOwner {
        addressToPreSaleEntry[_address] = true;
    }
    
    function setBaseURI(string memory baseURI) public onlyOwner {
        _baseTokenURI = baseURI;
    }

    function getBaseURI() public view returns (string memory){
        return _baseTokenURI;
    }
    function withdrawAll() public payable onlyOwner {
        require(payable(msg.sender).send(address(this).balance));
    }
}
