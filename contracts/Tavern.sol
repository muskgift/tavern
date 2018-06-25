pragma solidity ^0.4.24;

import "openzeppelin-zos/contracts/MerkleProof.sol";
import "zos-lib/contracts/migrations/Migratable.sol";
import "./TavernQuestReward.sol";

contract Tavern is Migratable {

    function initialize() isInitializer("Tavern", "0.0.1") public {
    }

    // Quest model
    struct Quest {
        address creator;
        uint index;
        string name;
        string hint;
        bytes32 merkleRoot;
        uint maxWinners;
        string metadata;
        bool valid;
        mapping (address => bool) winners;
        address[] winnersIndex;
        mapping (address => bool) claimers;
        address[] claimersIndex;
    }

    // State
    mapping (address => Quest[]) quests;
    mapping (address => mapping (address => uint[])) questsPerCreator;

    // Creates a new quest
    function createQuest(address _tokenAddress, string _name, string _hint, uint _maxWinners, bytes32 _merkleRoot, string _metadata) public {
        // If the quest is valid, create it
        Quest memory newQuest;
        uint questIndex = quests[_tokenAddress].length;
        newQuest.creator = msg.sender;
        newQuest.index = questIndex;
        newQuest.name = _name;
        newQuest.hint = _hint;
        newQuest.merkleRoot = _merkleRoot;
        newQuest.maxWinners = _maxWinners;
        newQuest.metadata = _metadata;

        // Save quest
        quests[_tokenAddress].push(newQuest);
        questsPerCreator[_tokenAddress][msg.sender].push(questIndex);

        // Validate quest
        validateQuest(_tokenAddress, questIndex);
    }

    // Alters the valid property of the given quest
    function validateQuest(address _tokenAddress, uint _questIndex) public {
        // Check the quest is invalid before trying to validate it
        require(quests[_tokenAddress][_questIndex].valid == false);

        TavernQuestReward tokenInterface = TavernQuestReward(_tokenAddress);
        quests[_tokenAddress][_questIndex].valid = tokenInterface.validateQuest(
            quests[_tokenAddress][_questIndex].name,
            quests[_tokenAddress][_questIndex].hint,
            quests[_tokenAddress][_questIndex].maxWinners,
            quests[_tokenAddress][_questIndex].merkleRoot,
            quests[_tokenAddress][_questIndex].metadata
        );
    }

    // Submits proof of quest completion and mints reward
    function submitProof(address _tokenAddress, uint _questIndex, bytes32[] _pathToRoot, bytes32 _proof) public {
        Quest memory quest = quests[_tokenAddress][_questIndex];

        // Check quest is valid
        require(quest.valid == true);

        // Avoid creating more winners after the max amount of tokens are minted
        require(quest.winnersIndex.length < quest.maxWinners);

        // Avoid the same winner spamming the contract
        require(!isWinner(_tokenAddress, _questIndex, msg.sender));

        // Avoid the creator winning their own quest
        require(msg.sender != quest.creator);

        // Verify merkle proof
        require(MerkleProof.verifyProof(_pathToRoot, quest.merkleRoot, _proof));

        // Add to winners list
        quests[_tokenAddress][_questIndex].winners[msg.sender] = true;
        quests[_tokenAddress][_questIndex].winnersIndex.push(msg.sender);

        // Mint reward
        claimReward(_tokenAddress, _questIndex);
    }

    // Claims the quest reward, if not already claimed
    function claimReward(address _tokenAddress, uint _questIndex) public {
        // Check if quest is valid
        require(quests[_tokenAddress][_questIndex].valid == true);
        // Check if the alledged winner is actually a winner
        require(isWinner(_tokenAddress, _questIndex, msg.sender));
        // Check if the winner is not in the in the claimers list yet
        require(!isClaimer(_tokenAddress, _questIndex, msg.sender));

        // NOTE: We used if instead of require in case manual validation of rewards want to be added
        // in the future, or if there's a bug in the token contract
        TavernQuestReward tokenInterface = TavernQuestReward(_tokenAddress);
        if(tokenInterface.rewardCompletion(this, msg.sender, _questIndex)) {
            // Add to claimers lists
            quests[_tokenAddress][_questIndex].claimers[msg.sender] = true;
            quests[_tokenAddress][_questIndex].claimersIndex.push(msg.sender);
        }
    }

    // Returns wheter or not the _allegedWinner is an actual winner
    function isWinner(address _tokenAddress, uint _questIndex, address _allegedWinner) public view returns (bool) {
        return quests[_tokenAddress][_questIndex].winners[_allegedWinner];
    }

    // Returns wheter or not the _allegedClaimer is an actual claimer
    function isClaimer(address _tokenAddress, uint _questIndex, address _allegedClaimer) public view returns (bool) {
        return quests[_tokenAddress][_questIndex].winners[_allegedClaimer];
    }
}
