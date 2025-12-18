----------------------------------------------------------------------------------------------------
-- TABLE BLOCK
----------------------------------------------------------------------------------------------------
TYPE block_number AS UINT64;
TYPE unix_timestamp AS TIMESTAMP(8){unit=second};
TYPE hash_as_hex AS CHAR(64); -- or: hash_as_base64 as VARCHAR(44)

TABLE blocks (
  number        block_number PRIMARY KEY, --#key-time-aligned
  hash          hash_as_hex,
  parent_number block_number,
  parent_hash   hash_as_hex,
  height        UINT64;
  timestamp     unix_timestamp
);

----------------------------------------------------------------------------------------------------
-- TABLE TRANSACTIONS
----------------------------------------------------------------------------------------------------
TYPE tx_index AS UINT32;
TYPE tx_version AS UINT16;
TYPE key_list AS LIST(VARCHAR);

TYPE address_st AS STRUCT(
     account_key LIST(VARCHAR),
     readonly_indexes LIST(UINT8),
     writeable_indexes LIST(UINT8)
);

TYPE address_lookup_list AS LIST(address_st);
TYPE signature_list AS LIST(VARCHAR);

TYPE loaded_addresses_st AS STRUCT(
     readonly LIST(VARCHAR),
     writable LIST(VARCHAR)
);

TABLE transactions (
    block_number                   block_number PRIMARY KEY, --#key-time-aligned
    transaction_index              tx_index     PRIMARY KEY,
    version                        tx_version,
    account_keys                   key_list,
    address_table_lookups          address_lookup_list,
    num_readonly_signed_accounts   UINT8,
    num_readonly_unsigned_accounts UINT8,
    num_required_signatures        UINT8,
    recent_blockhash               VARCHAR,
    signatures                     signature_list,
    err                            VARCHAR,
    compute_units_consumed         UINT64,
    fee                            UINT64,
    loaded_addresses               loaded_addresses_st,   
    has_dropped_log_messages       BOOLEAN,
    fee_payer                      VARCHAR,
    account_keys_size              UINT64,
    address_table_lookups_size     UINT64,
    signatures_size                UINT64,
    loaded_addresses_size          UINT64,
    accounts_bloom                 BLOB
);
