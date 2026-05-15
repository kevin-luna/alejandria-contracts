// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Alejandria — Registro de Propiedad Intelectual Académica
/// @notice Permite registrar, consultar y gestionar publicaciones académicas on-chain.
contract AlejandriaRegistry {

    // ─── Tipos ───────────────────────────────────────────────────────────────

    enum PublicationType {
        THESIS,       // Tesis doctoral
        TESINA,       // Tesina / tesis de licenciatura o maestría
        ARTICLE,      // Artículo científico
        JOURNAL,      // Número completo de revista
        PROCEEDINGS,  // Actas de congreso
        BOOK,         // Libro o capítulo de libro
        OTHER         // Otro tipo de publicación
    }

    struct Publication {
        uint256 id;
        string  title;
        string[] authorNames;
        address[] authorAddresses;
        PublicationType pubType;
        uint256 registrationDate;
        bytes32 contentHash;   // SHA-256 del documento
        string  institution;
        string  doi;           // DOI, ISBN u otro identificador externo
        string  ipfsHash;      // CID en IPFS para acceso descentralizado
        address registrant;
        bool    isActive;
    }

    struct RegisterParams {
        string title;
        string[] authorNames;
        address[] authorAddresses;
        PublicationType pubType;
        bytes32 contentHash;
        string institution;
        string doi;
        string ipfsHash;
    }

    struct UpdateParams {
        string title;
        string[] authorNames;
        address[] authorAddresses;
        string institution;
        string doi;
        string ipfsHash;
    }

    // ─── Estado ───────────────────────────────────────────────────────────────

    address public admin;
    uint256 private _count;

    mapping(uint256 => Publication) private _publications;
    mapping(bytes32  => uint256)    private _hashToId;

    // ─── Eventos ─────────────────────────────────────────────────────────────

    event PublicationRegistered(
        uint256 indexed id,
        address indexed registrant,
        bytes32 indexed contentHash,
        PublicationType pubType
    );
    event PublicationUpdated(uint256 indexed id, address indexed updater);
    event PublicationRevoked(uint256 indexed id, address indexed revoker);
    event RegistrationTransferred(
        uint256 indexed id,
        address indexed from,
        address indexed to
    );
    event AdminTransferred(address indexed from, address indexed to);

    // ─── Errores ─────────────────────────────────────────────────────────────

    error NotAuthorized();
    error PublicationNotFound(uint256 id);
    error PublicationInactive(uint256 id);
    error ContentHashAlreadyRegistered(bytes32 contentHash);
    error InvalidContentHash();
    error EmptyTitle();
    error ZeroAddress();

    // ─── Modificadores ────────────────────────────────────────────────────────

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAuthorized();
        _;
    }

    modifier onlyRegistrantOrAdmin(uint256 id) {
        Publication storage pub = _publications[id];
        if (pub.registrant != msg.sender && msg.sender != admin)
            revert NotAuthorized();
        _;
    }

    modifier exists(uint256 id) {
        if (id == 0 || id > _count) revert PublicationNotFound(id);
        _;
    }

    modifier active(uint256 id) {
        if (!_publications[id].isActive) revert PublicationInactive(id);
        _;
    }

    // ─── Constructor ─────────────────────────────────────────────────────────

    constructor() {
        admin = msg.sender;
    }

    // ─── Escritura ────────────────────────────────────────────────────────────

    /// @notice Registra una nueva publicación académica.
    /// @param p Parámetros de la publicación; p.contentHash debe ser el SHA-256 del documento.
    /// @return id Identificador único asignado a la publicación.
    function register(RegisterParams memory p) external returns (uint256 id) {
        if (bytes(p.title).length == 0)  revert EmptyTitle();
        if (p.contentHash == bytes32(0)) revert InvalidContentHash();
        if (_hashToId[p.contentHash] != 0)
            revert ContentHashAlreadyRegistered(p.contentHash);

        id = ++_count;

        _publications[id] = Publication({
            id:               id,
            title:            p.title,
            authorNames:      p.authorNames,
            authorAddresses:  p.authorAddresses,
            pubType:          p.pubType,
            registrationDate: block.timestamp,
            contentHash:      p.contentHash,
            institution:      p.institution,
            doi:              p.doi,
            ipfsHash:         p.ipfsHash,
            registrant:       msg.sender,
            isActive:         true
        });

        _hashToId[p.contentHash] = id;

        emit PublicationRegistered(id, msg.sender, p.contentHash, p.pubType);
    }

    /// @notice Desactiva una publicación (no la elimina; preserva el historial).
    function revoke(uint256 id)
        external exists(id) active(id) onlyRegistrantOrAdmin(id)
    {
        _publications[id].isActive = false;
        emit PublicationRevoked(id, msg.sender);
    }

    /// @notice Transfiere el derecho de gestión de la publicación a otra dirección.
    function transferRegistration(uint256 id, address newRegistrant)
        external exists(id) active(id) onlyRegistrantOrAdmin(id)
    {
        if (newRegistrant == address(0)) revert ZeroAddress();
        address old = _publications[id].registrant;
        _publications[id].registrant = newRegistrant;
        emit RegistrationTransferred(id, old, newRegistrant);
    }

    /// @notice Transfiere el rol de administrador del contrato.
    function transferAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        emit AdminTransferred(admin, newAdmin);
        admin = newAdmin;
    }

    // ─── Consultas ────────────────────────────────────────────────────────────

    /// @notice Devuelve todos los datos de una publicación por su ID.
    function getPublication(uint256 id)
        external view exists(id)
        returns (Publication memory)
    {
        return _publications[id];
    }

    /// @notice Comprueba si un hash de contenido ya está registrado y en qué ID.
    /// @return registered true si el hash pertenece a una publicación activa.
    /// @return id         ID de la publicación (0 si no existe o está revocada).
    function verifyByHash(bytes32 contentHash)
        external view
        returns (bool registered, uint256 id)
    {
        id = _hashToId[contentHash];
        registered = id != 0 && _publications[id].isActive;
    }

    /// @notice Total de publicaciones registradas (incluyendo revocadas).
    function totalPublications() external view returns (uint256) {
        return _count;
    }
}
