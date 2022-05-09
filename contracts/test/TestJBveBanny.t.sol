// SPDX-License-Identifier: MIT
pragma solidity 0.8.6;

import './helpers/TestBaseWorkflow.t.sol';
import '../veERC721.sol';
import '../interfaces/IJBVeTokenUriResolver.sol';

contract JBveBannyTests is TestBaseWorkflow {
  //*********************************************************************//
  // --------------------- private stored properties ------------------- //
  //*********************************************************************//
  JBveBanny private _jbveBanny;
  JBVeTokenUriResolver private _jbveTokenUriResolver;
  JBTokenStore private _jbTokenStore;
  JBController private _jbController;
  JBOperatorStore private _jbOperatorStore;
  uint256 private _projectId;
  address private _projectOwner;

  //*********************************************************************//
  // --------------------------- test setup ---------------------------- //
  //*********************************************************************//
  function setUp() public override {
    // calling before each for TestBaseWorkflow
    super.setUp();
    // fetching instances deployed in the base workflow file
    _projectId = projectID();
    _jbTokenStore = jbTokenStore();
    _jbOperatorStore = jbOperatorStore();
    _jbveTokenUriResolver = jbveTokenUriResolver();
    _jbController = jbController();

    // lock duration options array to be used for mock deployment
    // All have to be dividable by weeks
    uint256[] memory _lockDurationOptions = new uint256[](3);
    _lockDurationOptions[0] = 604800; // 1 week
    _lockDurationOptions[1] = 2419200; // 4 weeks
    _lockDurationOptions[2] = 7257600; // 12 weeks

    // JBveBanny
    _jbveBanny = new JBveBanny(
      _projectId,
      'Banny',
      'Banny',
      IJBVeTokenUriResolver(address(_jbveTokenUriResolver)),
      IJBTokenStore(address(_jbTokenStore)),
      IJBOperatorStore(address(_jbOperatorStore)),
      _lockDurationOptions
    );
  }

  function testConstructor() public {
    // All have to be dividable by weeks
    uint256[] memory _lockDurationOptions = new uint256[](3);
    _lockDurationOptions[0] = 604800; // 1 week
    _lockDurationOptions[1] = 2419200; // 4 weeks
    _lockDurationOptions[2] = 7257600; // 12 weeks
    // assertion checks for constructor code
    assertEq(address(_jbTokenStore.tokenOf(_projectId)), address(_jbveBanny.token()));
    assertEq(address(_jbveTokenUriResolver), address(_jbveBanny.uriResolver()));
    assertEq(_projectId, _jbveBanny.projectId());
    assertEq(_lockDurationOptions[0], _jbveBanny.lockDurationOptions()[0]);
  }

  function mintIJBTokens() public returns (IJBToken) {
    IJBToken _token = _jbTokenStore.tokenOf(_projectId);
    _projectOwner = projectOwner();
    evm.startPrank(_projectOwner);
    _jbController.mintTokensOf(_projectId, 100 ether, _projectOwner, 'Test Memo', true, true);
    _token.approve(_projectId, address(_jbveBanny), 10 ether);
    return _token;
  }

  function testLockWithJBToken() public {
    mintIJBTokens();
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (int128 _amount, , uint256 _duration, bool _useJbToken, bool _allowPublicExtension) = _jbveBanny
      .locked(1);
    assert(_jbveBanny.tokenVotingPowerAt(1, block.number) > 0);
    assertEq(_amount, 10 ether);
    assertEq(_duration, 604800);
    assert(_useJbToken);
    assert(!_allowPublicExtension);
    assertEq(_jbveBanny.ownerOf(1), _projectOwner);
    (uint256 amount, uint256 duration, , bool isJbToken, ) = _jbveBanny.getSpecs(1);
    assertEq(amount, 10 ether);
    assertEq(duration, 604800);
    assert(isJbToken);
  }

  function testUnlockingTokens() public {
    IJBToken _token = mintIJBTokens();
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, , uint256 lockedUntil, , ) = _jbveBanny.getSpecs(1);
    evm.warp(lockedUntil + 2);
    _jbveBanny.approve(address(_jbveBanny), 1);
    JBUnlockData[] memory unlocks = new JBUnlockData[](1);
    unlocks[0] = JBUnlockData(1, _projectOwner);
    _jbveBanny.unlock(unlocks);
    assert(_jbveBanny.tokenVotingPowerAt(1, block.number) == 0);
    (int128 _amount, uint256 end, , , ) = _jbveBanny.locked(1);
    assertEq(_amount, 0);
    assertEq(end, 0);
    assertEq(_token.balanceOf(address(_jbveBanny), _projectId), 0);
  }

  function testExtendLock() public {
    mintIJBTokens();
    uint256 _tokenId = _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, uint256 d, uint256 lockedUntil, , ) = _jbveBanny.getSpecs(_tokenId);
    assertEq(d, 604800);
    evm.warp(lockedUntil + 2);

    JBLockExtensionData[] memory extends = new JBLockExtensionData[](1);
    extends[0] = JBLockExtensionData(1, 2419200);
    _tokenId = _jbveBanny.extendLock(extends)[0];

    (, uint256 duration, , , ) = _jbveBanny.getSpecs(_tokenId);
    assertEq(duration, 2419200);
  }

  function testScenarioWithInvalidLockDuration() public {
    mintIJBTokens();
    evm.expectRevert(abi.encodeWithSignature('INVALID_LOCK_DURATION()'));
    _jbveBanny.lock(_projectOwner, 10 ether, 864001, _projectOwner, true, false);
  }

  function testScenarioWithInsufficientBalance() public {
    mintIJBTokens();
    evm.expectRevert(abi.encodeWithSignature('INSUFFICIENT_BALANCE()'));
    _jbveBanny.lock(_projectOwner, 101 ether, 604800, _projectOwner, true, false);
  }

  function testScenarioWhenLockPeriodIsNotOver() public {
    mintIJBTokens();
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, , uint256 lockedUntil, , ) = _jbveBanny.getSpecs(1);
    evm.warp(lockedUntil - 2);
    _jbveBanny.approve(address(_jbveBanny), 1);
    evm.expectRevert(abi.encodeWithSignature('LOCK_PERIOD_NOT_OVER()'));
    JBUnlockData[] memory unlocks = new JBUnlockData[](1);
    unlocks[0] = JBUnlockData(1, _projectOwner);
    _jbveBanny.unlock(unlocks);
  }

  function testScenarioWithInvalidLockDurationWhenExtendingDuration() public {
    mintIJBTokens();
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, uint256 d, uint256 lockedUntil, , ) = _jbveBanny.getSpecs(1);
    assertEq(d, 604800);
    evm.warp(lockedUntil + 2);
    evm.expectRevert(abi.encodeWithSignature('INVALID_LOCK_DURATION()'));

    JBLockExtensionData[] memory extends = new JBLockExtensionData[](1);
    extends[0] = JBLockExtensionData(1, 2419201);
    _jbveBanny.extendLock(extends);
  }

  function testScenarioWithInvalidLockExtension() public {
    mintIJBTokens();
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, uint256 d, uint256 lockedUntil, , ) = _jbveBanny.getSpecs(1);
    assertEq(d, 604800);
    evm.warp(lockedUntil / 2);
    evm.expectRevert(abi.encodeWithSignature('INVALID_LOCK_EXTENSION()'));

    JBLockExtensionData[] memory extends = new JBLockExtensionData[](1);
    extends[0] = JBLockExtensionData(1, 2419200);
    _jbveBanny.extendLock(extends);
  }

  function testLockWithNonJbToken() public {
    _projectOwner = projectOwner();
    evm.startPrank(_projectOwner);
    _jbController.mintTokensOf(_projectId, 100 ether, _projectOwner, 'Test Memo', false, true);
    uint256[] memory _permissionIndexes = new uint256[](1);
    _permissionIndexes[0] = JBOperations.TRANSFER;
    jbOperatorStore().setOperator(
      JBOperatorData(address(_jbveBanny), _projectId, _permissionIndexes)
    );
    _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, false, false);
    assert(_jbveBanny.tokenVotingPowerAt(1, block.number) > 0);
    (int128 _amount, , uint256 _duration, bool _useJbToken, bool _allowPublicExtension) = _jbveBanny
      .locked(1);
    assertEq(_amount, 10 ether);
    assertEq(_duration, 604800);
    assert(!_useJbToken);
    assert(!_allowPublicExtension);
    assertEq(_jbveBanny.ownerOf(1), _projectOwner);
    (uint256 amount, uint256 duration, , , ) = _jbveBanny.getSpecs(1);
    assertEq(amount, 10 ether);
    assertEq(duration, 604800);
  }

  function testLockVotingPowerIncreasesIfLockedLonger() public {
    mintIJBTokens();

    _jbveBanny.lock(_projectOwner, 5 ether, 604800, _projectOwner, true, false);
    assert(_jbveBanny.tokenVotingPowerAt(1, block.number) > 0);

    _jbveBanny.lock(_projectOwner, 5 ether, 2419200, _projectOwner, true, false);
    assert(_jbveBanny.tokenVotingPowerAt(2, block.number) > 0);

    // Since lock-2 is 4x as long as lock-1, it should have x4 the voting power
    // (might be slightly more or less due to rounding to nearest week)
    assertGt(
      _jbveBanny.tokenVotingPowerAt(2, block.number),
      _jbveBanny.tokenVotingPowerAt(1, block.number) * 4
    );
  }

  function testLockVotingPowerDecreasesOverTime() public {
    mintIJBTokens();

    uint256 _steps = 4;
    uint256 _secondsPerBlock = 1;
    uint256 _lastVotingPower = 0;
    uint256 _tokenId = _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, uint256 _end, , , ) = _jbveBanny.locked(_tokenId);

    uint256 _timePerStep = (_end - block.timestamp) / _steps + 1;
    uint256 _blocksPerStep = _timePerStep / _secondsPerBlock;

    // Increase the current timestamp and verify that the voting power keeps decreasing
    uint256 _currentTime = block.timestamp;
    uint256 _currentBlock = block.number;

    for (uint256 _i; _i < _steps; _i++) {
      uint256 _currentVotingPower = _jbveBanny.tokenVotingPowerAt(_tokenId, _currentBlock);

      if (_lastVotingPower != 0) {
        assertLt(_currentVotingPower, _lastVotingPower);
      }
      assertTrue(_currentVotingPower > 0);

      _lastVotingPower = _currentVotingPower;

      _currentTime += _timePerStep;
      _currentBlock += _blocksPerStep; // Assuming 15 second block times

      evm.warp(_currentTime);
      evm.roll(_currentBlock);
    }

    // After the lock has expired it should be 0
    assert(_jbveBanny.tokenVotingPowerAt(_tokenId, _currentBlock) == 0);
  }

  function testLockVotingPowerHistoricLookupIsCorrect() public {
    mintIJBTokens();

    uint256 _steps = 4;
    uint256 _secondsPerBlock = 1;
    uint256 _lastVotingPower = 0;
    uint256 _tokenId = _jbveBanny.lock(_projectOwner, 10 ether, 604800, _projectOwner, true, false);
    (, uint256 _end, , , ) = _jbveBanny.locked(_tokenId);

    uint256[] memory _historicVotingPower = new uint256[](_steps);
    uint256[] memory _historicVotingPowerBlocks = new uint256[](_steps);

    uint256 _timePerStep = (_end - block.timestamp) / _steps + 1;
    uint256 _blocksPerStep = _timePerStep / _secondsPerBlock;

    // Increase the current timestamp and verify that the voting power keeps decreasing
    uint256 _currentTime = block.timestamp;
    uint256 _currentBlock = block.number;

    // Check the voting power and check if it decreases in comparison with the previous check
    // Store the `_currentVotingPower`
    for (uint256 _i; _i < _steps; _i++) {
      uint256 _currentVotingPower = _jbveBanny.tokenVotingPowerAt(_tokenId, _currentBlock);

      if (_lastVotingPower != 0) {
        assertLt(_currentVotingPower, _lastVotingPower);
      }
      assertTrue(_currentVotingPower > 0);

      _historicVotingPower[_i] = _currentVotingPower;
      _historicVotingPowerBlocks[_i] = _currentBlock;
      _lastVotingPower = _currentVotingPower;

      _currentTime += _timePerStep;
      _currentBlock += _blocksPerStep; // Assuming 15 second block times

      evm.warp(_currentTime);
      evm.roll(_currentBlock);
    }

    // After the lock has expired it should be 0
    assert(_jbveBanny.tokenVotingPowerAt(_tokenId, _currentBlock) == 0);

    // Use the stored `_currentVotingPower` and `_currentBlock` and perform historic lookups for each
    // Make sure the historic lookup and (at the time) current values are the same
    for (uint256 _i = 0; _i < _historicVotingPower.length; _i++) {
      uint256 _votingPowerAtBlock = _jbveBanny.tokenVotingPowerAt(
        _tokenId,
        _historicVotingPowerBlocks[_i]
      );

      assertEq(_historicVotingPower[_i], _votingPowerAtBlock);
      assert(_historicVotingPower[_i] > 0 && _votingPowerAtBlock > 0);
    }
  }
}
