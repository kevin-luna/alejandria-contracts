// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AlejandriaRegistry} from "./AlejandriaRegistry.sol";
import {Test} from "forge-std/Test.sol";

contract AlejandriaRegistryTest is Test {

    AlejandriaRegistry registry;

    address admin   = address(1);
    address alice   = address(2);
    address bob     = address(3);
    address charlie = address(4);

    bytes32 constant HASH_A = keccak256("documento-tesis-alice");
    bytes32 constant HASH_B = keccak256("documento-articulo-bob");

    string[] emptyNames;
    address[] emptyAddrs;

    function setUp() public {
        vm.prank(admin);
        registry = new AlejandriaRegistry();
    }

    // --- register ---

    function test_Register_AssignsSequentialId() public {
        vm.startPrank(alice);
        uint256 id1 = _registerDefault(HASH_A);
        uint256 id2 = _registerDefault(keccak256("otro-doc"));
        vm.stopPrank();

        assertEq(id1, 1);
        assertEq(id2, 2);
        assertEq(registry.totalPublications(), 2);
    }

    function test_Register_StoresMetadata() public {
        vm.prank(alice);
        string[] memory names = new string[](1);
        names[0] = "Alice";
        address[] memory addrs = new address[](1);
        addrs[0] = alice;

        uint256 id = registry.register(
            AlejandriaRegistry.RegisterParams({
                title:            "Mi Tesis",
                authorNames:      names,
                authorAddresses:  addrs,
                pubType:          AlejandriaRegistry.PublicationType.THESIS,
                contentHash:      HASH_A,
                institution:      "UNAM",
                doi:              "10.1234/test",
                ipfsHash:         "QmHash123"
            })
        );

        AlejandriaRegistry.Publication memory pub = registry.getPublication(id);
        assertEq(pub.title, "Mi Tesis");
        assertEq(pub.authorNames[0], "Alice");
        assertEq(pub.authorAddresses[0], alice);
        assertEq(uint8(pub.pubType), uint8(AlejandriaRegistry.PublicationType.THESIS));
        assertEq(pub.contentHash, HASH_A);
        assertEq(pub.institution, "UNAM");
        assertEq(pub.doi, "10.1234/test");
        assertEq(pub.ipfsHash, "QmHash123");
        assertEq(pub.registrant, alice);
        assertTrue(pub.isActive);
    }

    function test_Register_EmitEvent() public {
        vm.expectEmit(true, true, true, true);
        emit AlejandriaRegistry.PublicationRegistered(
            1, alice, HASH_A, AlejandriaRegistry.PublicationType.ARTICLE
        );
        vm.prank(alice);
        registry.register(
            AlejandriaRegistry.RegisterParams({
                title:           "Articulo de prueba",
                authorNames:     emptyNames,
                authorAddresses: emptyAddrs,
                pubType:         AlejandriaRegistry.PublicationType.ARTICLE,
                contentHash:     HASH_A,
                institution:     "",
                doi:             "",
                ipfsHash:        ""
            })
        );
    }

    function test_Register_RevertOn_EmptyTitle() public {
        vm.prank(alice);
        vm.expectRevert(AlejandriaRegistry.EmptyTitle.selector);
        registry.register(
            AlejandriaRegistry.RegisterParams({
                title: "", authorNames: emptyNames, authorAddresses: emptyAddrs,
                pubType: AlejandriaRegistry.PublicationType.OTHER,
                contentHash: HASH_A, institution: "", doi: "", ipfsHash: ""
            })
        );
    }

    function test_Register_RevertOn_ZeroHash() public {
        vm.prank(alice);
        vm.expectRevert(AlejandriaRegistry.InvalidContentHash.selector);
        registry.register(
            AlejandriaRegistry.RegisterParams({
                title: "Titulo", authorNames: emptyNames, authorAddresses: emptyAddrs,
                pubType: AlejandriaRegistry.PublicationType.OTHER,
                contentHash: bytes32(0), institution: "", doi: "", ipfsHash: ""
            })
        );
    }

    function test_Register_RevertOn_DuplicateHash() public {
        vm.startPrank(alice);
        _registerDefault(HASH_A);
        vm.expectRevert(
            abi.encodeWithSelector(
                AlejandriaRegistry.ContentHashAlreadyRegistered.selector,
                HASH_A
            )
        );
        _registerDefault(HASH_A);
        vm.stopPrank();
    }

    // --- verifyByHash ---

    function test_VerifyByHash_ActivePublication() public {
        vm.prank(alice);
        _registerDefault(HASH_A);

        (bool registered, uint256 id) = registry.verifyByHash(HASH_A);
        assertTrue(registered);
        assertEq(id, 1);
    }

    function test_VerifyByHash_UnknownHash() public view {
        (bool registered, uint256 id) = registry.verifyByHash(HASH_B);
        assertFalse(registered);
        assertEq(id, 0);
    }

    function test_VerifyByHash_RevokedPublication() public {
        vm.startPrank(alice);
        uint256 id = _registerDefault(HASH_A);
        registry.revoke(id);
        vm.stopPrank();

        (bool registered,) = registry.verifyByHash(HASH_A);
        assertFalse(registered);
    }

    // --- revoke ---

    function test_Revoke_DeactivatesPublication() public {
        vm.startPrank(alice);
        uint256 id = _registerDefault(HASH_A);
        registry.revoke(id);
        vm.stopPrank();

        AlejandriaRegistry.Publication memory pub = registry.getPublication(id);
        assertFalse(pub.isActive);
    }

    function test_Revoke_RevertOn_AlreadyRevoked() public {
        vm.startPrank(alice);
        uint256 id = _registerDefault(HASH_A);
        registry.revoke(id);
        vm.expectRevert(
            abi.encodeWithSelector(AlejandriaRegistry.PublicationInactive.selector, id)
        );
        registry.revoke(id);
        vm.stopPrank();
    }

    // --- transferRegistration ---

    function test_TransferRegistration_RevertOn_ZeroAddress() public {
        vm.prank(alice);
        uint256 id = _registerDefault(HASH_A);

        vm.prank(alice);
        vm.expectRevert(AlejandriaRegistry.ZeroAddress.selector);
        registry.transferRegistration(id, address(0));
    }

    // --- transferAdmin ---

    function test_TransferAdmin() public {
        vm.prank(admin);
        registry.transferAdmin(bob);
        assertEq(registry.admin(), bob);
    }

    function test_TransferAdmin_RevertOn_NonAdmin() public {
        vm.prank(alice);
        vm.expectRevert(AlejandriaRegistry.NotAuthorized.selector);
        registry.transferAdmin(alice);
    }

    // --- getPublication errors ---

    function test_GetPublication_RevertOn_InvalidId() public {
        vm.expectRevert(
            abi.encodeWithSelector(AlejandriaRegistry.PublicationNotFound.selector, 99)
        );
        registry.getPublication(99);
    }

    // --- fuzz ---

    function testFuzz_Register_UniqueHashes(bytes32 h1, bytes32 h2) public {
        vm.assume(h1 != bytes32(0) && h2 != bytes32(0) && h1 != h2);
        vm.startPrank(alice);
        registry.register(
            AlejandriaRegistry.RegisterParams({
                title: "Doc 1", authorNames: emptyNames, authorAddresses: emptyAddrs,
                pubType: AlejandriaRegistry.PublicationType.OTHER,
                contentHash: h1, institution: "", doi: "", ipfsHash: ""
            })
        );
        registry.register(
            AlejandriaRegistry.RegisterParams({
                title: "Doc 2", authorNames: emptyNames, authorAddresses: emptyAddrs,
                pubType: AlejandriaRegistry.PublicationType.OTHER,
                contentHash: h2, institution: "", doi: "", ipfsHash: ""
            })
        );
        vm.stopPrank();

        assertEq(registry.totalPublications(), 2);
    }

    // --- helper ---

    function _registerDefault(bytes32 hash) internal returns (uint256) {
        return registry.register(
            AlejandriaRegistry.RegisterParams({
                title:           "Publicacion de prueba",
                authorNames:     emptyNames,
                authorAddresses: emptyAddrs,
                pubType:         AlejandriaRegistry.PublicationType.OTHER,
                contentHash:     hash,
                institution:     "Universidad de prueba",
                doi:             "10.0000/test",
                ipfsHash:        ""
            })
        );
    }
}
