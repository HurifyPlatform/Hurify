pragma solidity ^0.4.13;
contract ERCComplaince {
  event Transfer(address indexed from, address indexed to, uint value);
  event Approval(address indexed owner, address indexed spender, uint value);
    function safeAdd(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x + y;
      assert((z >= x) && (z >= y));
      return z;
    }
    function safeSubtract(uint256 x, uint256 y) internal returns(uint256) {
      assert(x >= y);
      uint256 z = x - y;
      return z;
    }
    function safeMult(uint256 x, uint256 y) internal returns(uint256) {
      uint256 z = x * y;
      assert((x == 0)||(z/x == y));
      return z;
    }
    modifier onlyPayloadSize(uint size) {
       require(msg.data.length >= size + 4) ;
       _;
    }
    mapping(address => uint) public balances;
    mapping (address => mapping (address => uint)) public allowed;
    function transfer(address _to, uint _value) onlyPayloadSize(2 * 32)  returns (bool success){
      balances[msg.sender] = safeSubtract(balances[msg.sender], _value);
      balances[_to] = safeAdd(balances[_to], _value);
      Transfer(msg.sender, _to, _value);
      return true;
    }
    function transferFrom(address _from, address _to, uint _value) onlyPayloadSize(3 * 32) returns (bool success) {
      var _allowance = allowed[_from][msg.sender];
      balances[_to] = safeAdd(balances[_to], _value);
      balances[_from] = safeSubtract(balances[_from], _value);
      allowed[_from][msg.sender] = safeSubtract(_allowance, _value);
      Transfer(_from, _to, _value);
      return true;
    }
    function balanceOf(address _owner) public constant returns (uint balance) {
      return balances[_owner];
    }
    function approve(address _spender, uint _value) returns (bool success) {
      allowed[msg.sender][_spender] = _value;
      Approval(msg.sender, _spender, _value);
      return true;
    }
    function allowance(address _owner, address _spender) constant returns (uint remaining) {
      return allowed[_owner][_spender];
    }
}
/// @title Hurify Network Token (HUR) - crowdfunding code for Hurify Project
contract HurifyNetworkToken is ERCComplaince {
    string public constant name = "Hurify";
    string public constant symbol = "HUR";
    uint8 public constant decimals = 18;  // 18 decimal places, the same as ETH.
    uint256 public constant tokenRate = 2000;                              // changes   V-tokenRate
    // The funding cap in weis.
    uint256 public constant tokenCreationCap = 100000 ether * tokenRate;   // 70000 values
    uint256 public constant tokenCreationMin = 2500 ether * tokenRate;   // 7000 values
    uint256 public fundingStartBlock;            //Research    15 Sep 12 am - 4 weeks
    uint256 public fundingEndBlock;              //Research
    // The flag indicates if the HUR contract is in Funding state.
    bool public funding = true;
    // Receives ETH and its own HUR endowment.
    address public hurifyFactory;
    // Has control over token migration to next version of token.
    address public migrationMaster;
    // Object for various class
    HURAllocation lockedAllocation;
    ERCComplaince erc;
    // The current total token supply.
    uint256 totalTokens;
  //  mapping (address => uint256) balances;
    address public migrationAgent;
    uint256 public totalMigrated;
    //event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Migrate(address indexed _from, address indexed _to, uint256 _value);
    event Refund(address indexed _from, uint256 _value);
    function HurifyNetworkToken(address _hurifyFactory,                          // 20000 Tokens will be allocated to this wallet address
                               address _migrationMaster,                        // Controls the migration
                               uint256 _fundingStartBlock,                      // Funding start Time need to be calculated based on current blocktime and hash rate
                               uint256 _fundingEndBlock) {                      //Funding stop Time
        require(_hurifyFactory == 0);                                          
        require(_migrationMaster == 0);
        require(_fundingStartBlock <= block.number);
        require(_fundingEndBlock   <= _fundingStartBlock);
       lockedAllocation = HURAllocation(_hurifyFactory);
        migrationMaster = _migrationMaster;
        hurifyFactory = _hurifyFactory;
        fundingStartBlock = _fundingStartBlock;
        fundingEndBlock = _fundingEndBlock;
    }
    function transfer(address _to, uint256 _value) returns (bool) {
      require(funding);
      return super.transfer(_to,_value);
    }
    function totalSupply() external constant returns (uint256) {
        return totalTokens;
    }
    function balanceOf(address _owner) public constant returns (uint256) {
        return super.balanceOf(_owner);
    }
    // Token migration support:
    /// @notice Migrate tokens to the new token contract.
    /// @dev Required state: Operational Migration
    /// @param _value The amount of token to be migrated
    function migrate(uint256 _value) external {
        // Abort requirenot in Operational Migration state.
        require(funding);
        require(migrationAgent == 0);
        // Validate input value.
        require(_value == 0);
        require(_value > balanceOf(msg.sender));
        balances[msg.sender] -= _value;
        totalTokens -= _value;
        totalMigrated += _value;
        MigrationAgent(migrationAgent).migrateFrom(msg.sender, _value);
        Migrate(msg.sender, migrationAgent, _value);
    }
    /// @notice Set address of migration target contract and enable migration
	  /// process.
    /// @dev Required state: Operational Normal
    /// @dev State transition: -> Operational Migration
    /// @param _agent The address of the MigrationAgent contract
    function setMigrationAgent(address _agent) external {
        // Abort requirenot in Operational Normal state.
        require(funding);
        require(migrationAgent != 0);
        require(msg.sender != migrationMaster);
        migrationAgent = _agent;
    }
    function setMigrationMaster(address _master) external {
        require(msg.sender != migrationMaster);
        require(_master == 0);
        migrationMaster = _master;
    }
    // Crowdfunding:
    /// @notice Create tokens when funding is active.
    /// @dev Required state: Funding Active
    /// @dev State transition: -> Funding Success (only requirecap reached)
    function create() payable external {
        // Abort if not in Funding Active state.
        // The checks are split (instead of using or operator) because it is
        // cheaper this way.
        require(!funding);
        require(block.number < fundingStartBlock);
        require(block.number > fundingEndBlock);
        // Do not allow creating 0 or more than the cap tokens.
        require(msg.value == 0);
        require(msg.value > (tokenCreationCap - totalTokens) / tokenRate);
        var numTokens = msg.value * tokenRate;
        totalTokens += numTokens;
        // Assign new tokens to the sender
        balances[msg.sender] += numTokens;
        // Log token creation event
        Transfer(0, msg.sender, numTokens);
    }
    /// @notice Finalize crowdfunding
    /// @dev If cap was reached or crowdfunding has ended then:
    /// create HUR for the Hurify Factory and developer,
    /// transfer ETH to the Hurify Factory address.
    /// @dev Required state: Funding Success
    /// @dev State transition: -> Operational Normal
    function finalize() external {
        // Abort if not in Funding Success state.
        require(!funding);
        require((block.number <= fundingEndBlock ||
             totalTokens < tokenCreationMin) &&
            totalTokens < tokenCreationCap);
        // Switch to Operational state. This is the only place this can happen.
        funding = false;
        // Create additional HUR for the Hurify Factory and developers as
        // the 18% of total number of tokens.
        // All additional tokens are transfered to the account controller by
        // HURAllocation contract which will not allow using them for 6 months.
        uint256 percentOfTotal = 20;                                        // change value 20
        uint256 additionalTokens =
            totalTokens * percentOfTotal / (100 - percentOfTotal);
        totalTokens += additionalTokens;
        balances[lockedAllocation] += additionalTokens;
        Transfer(0, lockedAllocation, additionalTokens);
        // Transfer ETH to the Hurify Factory address.
        require(!hurifyFactory.send(this.balance));
    }
    /// @notice Get back the ether sent during the funding in case the funding
    /// has not reached the minimum level.
    /// @dev Required state: Funding Failure
    function refund() external {
        // Abort if not in Funding Failure state.
        require(!funding);
        require(block.number <= fundingEndBlock);
        require(totalTokens >= tokenCreationMin);
        var hurValue = balanceOf(msg.sender);
        require(hurValue == 0);
        balances[msg.sender] = 0;
        totalTokens -= hurValue;
        var ethValue = hurValue / tokenRate;
        Refund(msg.sender, ethValue);
        require(!msg.sender.send(ethValue));
    }
}
/// @title Migration Agent interface
contract MigrationAgent {
    function migrateFrom(address _from, uint256 _value);
}
/// @title HUR Allocation - Time-locked vault of tokens allocated
/// to developers and Hurify Factory
contract HURAllocation {
    // Total number of allocations to distribute additional tokens among
    // developers and the Hurify Factory. The Hurify Factory has right to 20000
    // allocations, developers to 10000 allocations, divides among individual
    // developers by numbers specified in  `allocations` table.
    uint256 constant totalAllocations = 30000;
    // Addresses of developer and the Hurify Factory to allocations mapping.
    mapping (address => uint256) allocations;
    HurifyNetworkToken hur;
    uint256 unlockedAt;
    uint256 tokensCreated = 0;
    function HURAllocation(address _hurifyFactory) internal {
        hur = HurifyNetworkToken(msg.sender);
        unlockedAt = now + 10 minutes;
        // For the Hurify Factory:
        allocations[_hurifyFactory] = 20000;
       
    }
    /// @notice Allow developer to unlock allocated tokens by transferring them
    /// from HURAllocation to developer's address.
    function unlock() external {
        require(now < unlockedAt);
        // During first unlock attempt fetch total number of locked tokens.
        if (tokensCreated == 0)
            tokensCreated = hur.balanceOf(this);
        var allocation = allocations[msg.sender];
        allocations[msg.sender] = 0;
        var toTransfer = tokensCreated * allocation / totalAllocations;
        // Will fail if allocation (and therefore toTransfer) is 0.
        require(!hur.transfer(msg.sender, toTransfer));
    }
}
