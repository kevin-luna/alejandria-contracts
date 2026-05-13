import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { keccak256, toBytes, zeroAddress, zeroHash } from "viem";

const HASH_A = keccak256(toBytes("documento-tesis-alice"));
const HASH_B = keccak256(toBytes("documento-articulo-bob"));

const PublicationType = {
  THESIS:      0,
  TESINA:      1,
  ARTICLE:     2,
  JOURNAL:     3,
  PROCEEDINGS: 4,
  BOOK:        5,
  OTHER:       6,
} as const;

type PubType = (typeof PublicationType)[keyof typeof PublicationType];

describe("AlejandriaRegistry", async function () {
  const { viem } = await network.create();
  const [admin, alice, bob, charlie] = await viem.getWalletClients();

  async function deployRegistry() {
    return viem.deployContract("AlejandriaRegistry");
  }

  function makeRegisterParams(
    hash = HASH_A,
    pubType: PubType = PublicationType.OTHER,
    overrides: Partial<{
      title: string;
      authorNames: string[];
      authorAddresses: `0x${string}`[];
      institution: string;
      doi: string;
      ipfsHash: string;
    }> = {},
  ) {
    return {
      title:           "Publicacion de prueba",
      authorNames:     [] as string[],
      authorAddresses: [] as `0x${string}`[],
      pubType,
      contentHash:     hash,
      institution:     "Universidad de prueba",
      doi:             "10.0000/test",
      ipfsHash:        "",
      ...overrides,
    } as const;
  }

  function registerDefault(
    registry: Awaited<ReturnType<typeof deployRegistry>>,
    hash = HASH_A,
    sender = alice,
    pubType: PubType = PublicationType.OTHER,
  ) {
    return registry.write.register([makeRegisterParams(hash, pubType)], {
      account: sender.account,
    });
  }

  // --- register ---

  it("register: asigna IDs secuenciales", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registerDefault(registry, HASH_B);
    assert.equal(await registry.read.totalPublications(), 2n);
  });

  it("register: almacena metadatos correctamente", async () => {
    const registry = await deployRegistry();
    await registry.write.register(
      [
        makeRegisterParams(HASH_A, PublicationType.THESIS, {
          title:           "Mi Tesis",
          authorNames:     ["Alice"],
          authorAddresses: [alice.account.address],
          institution:     "UNAM",
          doi:             "10.1234/test",
          ipfsHash:        "QmHash123",
        }),
      ],
      { account: alice.account },
    );

    const pub = await registry.read.getPublication([1n]);
    assert.equal(pub.title, "Mi Tesis");
    assert.equal(pub.pubType, PublicationType.THESIS);
    assert.equal(pub.contentHash, HASH_A);
    assert.equal(pub.institution, "UNAM");
    assert.equal(pub.doi, "10.1234/test");
    assert.equal(pub.ipfsHash, "QmHash123");
    assert.equal(pub.registrant.toLowerCase(), alice.account.address.toLowerCase());
    assert.equal(pub.isActive, true);
  });

  it("register: emite evento PublicationRegistered", async () => {
    const registry = await deployRegistry();
    const publicClient = await viem.getPublicClient();
    const blockBefore = await publicClient.getBlockNumber();

    await registerDefault(registry, HASH_A, alice, PublicationType.ARTICLE);

    const events = await publicClient.getContractEvents({
      address: registry.address,
      abi: registry.abi,
      eventName: "PublicationRegistered",
      fromBlock: blockBefore,
      strict: true,
    });

    assert.equal(events.length, 1);
    assert.equal(events[0].args.id, 1n);
    assert.equal(events[0].args.contentHash, HASH_A);
    assert.equal(events[0].args.pubType, PublicationType.ARTICLE);
  });

  it("register: revierte con título vacío", async () => {
    const registry = await deployRegistry();
    await assert.rejects(
      registry.write.register(
        [makeRegisterParams(HASH_A, PublicationType.OTHER, { title: "" })],
        { account: alice.account },
      ),
      /EmptyTitle/,
    );
  });

  it("register: revierte con hash cero", async () => {
    const registry = await deployRegistry();
    await assert.rejects(
      registry.write.register(
        [{ ...makeRegisterParams(), contentHash: zeroHash }],
        { account: alice.account },
      ),
      /InvalidContentHash/,
    );
  });

  it("register: revierte con hash duplicado", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await assert.rejects(registerDefault(registry, HASH_A), /ContentHashAlreadyRegistered/);
  });

  // --- verifyByHash ---

  it("verifyByHash: devuelve true para publicación activa", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    const [registered, id] = await registry.read.verifyByHash([HASH_A]);
    assert.equal(registered, true);
    assert.equal(id, 1n);
  });

  it("verifyByHash: devuelve false para hash desconocido", async () => {
    const registry = await deployRegistry();
    const [registered, id] = await registry.read.verifyByHash([HASH_B]);
    assert.equal(registered, false);
    assert.equal(id, 0n);
  });

  it("verifyByHash: devuelve false para publicación revocada", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.revoke([1n], { account: alice.account });
    const [registered] = await registry.read.verifyByHash([HASH_A]);
    assert.equal(registered, false);
  });

  // --- getByRegistrant / getByAuthor ---

  it("getByRegistrant: lista las publicaciones del registrante", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registerDefault(registry, HASH_B);
    const ids = await registry.read.getByRegistrant([alice.account.address]);
    assert.deepEqual(ids, [1n, 2n]);
  });

  it("getByAuthor: indexa las direcciones de autores", async () => {
    const registry = await deployRegistry();
    await registry.write.register(
      [makeRegisterParams(HASH_A, PublicationType.ARTICLE, {
        title:           "Paper conjunto",
        authorAddresses: [charlie.account.address],
      })],
      { account: alice.account },
    );
    const ids = await registry.read.getByAuthor([charlie.account.address]);
    assert.equal(ids.length, 1);
    assert.equal(ids[0], 1n);
  });

  // --- update ---

  it("update: modifica metadatos sin cambiar el hash", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.update(
      [1n, { title: "Titulo nuevo", authorNames: [], authorAddresses: [], institution: "MIT", doi: "10.9999/x", ipfsHash: "QmNew" }],
      { account: alice.account },
    );
    const pub = await registry.read.getPublication([1n]);
    assert.equal(pub.title, "Titulo nuevo");
    assert.equal(pub.institution, "MIT");
    assert.equal(pub.contentHash, HASH_A);
  });

  it("update: el admin puede modificar cualquier publicación", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.update(
      [1n, { title: "Corregido por admin", authorNames: [], authorAddresses: [], institution: "", doi: "", ipfsHash: "" }],
      { account: admin.account },
    );
    const pub = await registry.read.getPublication([1n]);
    assert.equal(pub.title, "Corregido por admin");
  });

  it("update: revierte si el llamante no está autorizado", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await assert.rejects(
      registry.write.update(
        [1n, { title: "Hacked", authorNames: [], authorAddresses: [], institution: "", doi: "", ipfsHash: "" }],
        { account: bob.account },
      ),
      /NotAuthorized/,
    );
  });

  // --- revoke ---

  it("revoke: desactiva la publicación", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.revoke([1n], { account: alice.account });
    const pub = await registry.read.getPublication([1n]);
    assert.equal(pub.isActive, false);
  });

  it("revoke: revierte si ya está revocada", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.revoke([1n], { account: alice.account });
    await assert.rejects(
      registry.write.revoke([1n], { account: alice.account }),
      /PublicationInactive/,
    );
  });

  // --- transferRegistration ---

  it("transferRegistration: cambia el propietario", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await registry.write.transferRegistration([1n, bob.account.address], { account: alice.account });
    const pub = await registry.read.getPublication([1n]);
    assert.equal(pub.registrant.toLowerCase(), bob.account.address.toLowerCase());
  });

  it("transferRegistration: revierte con dirección cero", async () => {
    const registry = await deployRegistry();
    await registerDefault(registry, HASH_A);
    await assert.rejects(
      registry.write.transferRegistration([1n, zeroAddress], { account: alice.account }),
      /ZeroAddress/,
    );
  });

  // --- transferAdmin ---

  it("transferAdmin: cambia el administrador", async () => {
    const registry = await deployRegistry();
    await registry.write.transferAdmin([bob.account.address], { account: admin.account });
    const newAdmin = await registry.read.admin();
    assert.equal(newAdmin.toLowerCase(), bob.account.address.toLowerCase());
  });

  it("transferAdmin: revierte si no es admin", async () => {
    const registry = await deployRegistry();
    await assert.rejects(
      registry.write.transferAdmin([alice.account.address], { account: alice.account }),
      /NotAuthorized/,
    );
  });

  // --- getPublication errors ---

  it("getPublication: revierte con ID inexistente", async () => {
    const registry = await deployRegistry();
    await assert.rejects(registry.read.getPublication([99n]), /PublicationNotFound/);
  });
});
