#include "blake2b.h"
#include "blockchain.h"
#include "ckb_dlfcn.h"
#include "ckb_syscalls.h"
#include "ckb_utils.h"
#include "secp256k1_helper.h"
#include <stdio.h>

#define BLAKE2B_BLOCK_SIZE 32
#define BLAKE160_SIZE 20
#define PUBKEY_SIZE 33
#define RECID_INDEX 64
#define SIGNATURE_SIZE 65
#define MAX_WITNESS_SIZE 32768
#define SCRIPT_SIZE 32768
#define TEMP_SIZE 32768
#define GPC_LOCK_ARGS_SIZE 57
#define MAX_CELL 100000
#define HASH_SIZE 32

#define ERROR_ARGUMENTS_LEN -1
#define ERROR_ENCODING -2
#define ERROR_SYSCALL -3
#define ERROR_SECP_RECOVER_PUBKEY -11
#define ERROR_SECP_VERIFICATION -12
#define ERROR_SECP_PARSE_PUBKEY -13
#define ERROR_SECP_PARSE_SIGNATURE -14
#define ERROR_SECP_SERIALIZE_PUBKEY -15
#define ERROR_SCRIPT_TOO_LONG -21
#define ERROR_WITNESS_SIZE -22
#define ERROR_PUBKEY_BLAKE160_HASH -31
#define ERROR_INVALID_PREFILLED_DATA_SIZE -41
#define ERROR_INVALID_SIGNATURE_SIZE -42
#define ERROR_INVALID_MESSAGE_SIZE -43
#define ERROR_INVALID_OUTPUT_SIZE -44
#define ERROR_NOUNCE_INVALID -60
#define ERROR_STATUS_INVALID -61
#define ERROR_SINCE_INVALID -62
#define ERROR_TYPE_SCRIPT_HASH_INCONSISTENT -63
#define ERROR_PUBKEY_INCONSISTENT -64
#define ERROR_CODE_HASH_INCONSISTENT -65
#define ERROR_HASH_TYPE_INCONSISTENT -66
#define ERROR_NOUNCE_INCONSISTENT -67
#define ERROR_FLAG_STATUS -68

int extract_witness_lock(uint8_t *witness, uint64_t len,
                         mol_seg_t *lock_bytes_seg)
{
    mol_seg_t witness_seg;
    witness_seg.ptr = witness;
    witness_seg.size = len;

    if (MolReader_WitnessArgs_verify(&witness_seg, false) != MOL_OK)
    {
        return ERROR_ENCODING;
    }
    mol_seg_t lock_seg = MolReader_WitnessArgs_get_lock(&witness_seg);

    if (MolReader_BytesOpt_is_none(&lock_seg))
    {
        return ERROR_ENCODING;
    }
    *lock_bytes_seg = MolReader_Bytes_raw_bytes(&lock_seg);
    return CKB_SUCCESS;
}

int extract_script_arg(uint8_t *script, uint64_t len, mol_seg_t *args_bytes_seg)

{
    mol_seg_t script_seg;
    script_seg.ptr = (uint8_t *)script;
    script_seg.size = len;
    if (MolReader_Script_verify(&script_seg, false) != MOL_OK)
    {
        return ERROR_ENCODING;
    }

    mol_seg_t args_seg = MolReader_Script_get_args(&script_seg);
    *args_bytes_seg = MolReader_Bytes_raw_bytes(&args_seg);
    if ((*args_bytes_seg).size != GPC_LOCK_ARGS_SIZE)
    {
        return ERROR_ARGUMENTS_LEN;
    }
    return CKB_SUCCESS;
}

int parse_lock_args(unsigned char *lock_script, uint64_t script_len,
                    uint8_t *status, uint64_t *lock_time,
                    uint64_t *nounce, uint8_t *pubkey_A, uint8_t *pubkey_B)
{
    mol_seg_t args_bytes_seg;
    int ret = extract_script_arg(lock_script, script_len, &args_bytes_seg);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_ENCODING;
    }
    uint8_t *lock_arg = (uint8_t *)args_bytes_seg.ptr;
    *status = lock_arg[0];
    *lock_time = *(uint64_t *)&lock_arg[1];
    *nounce = *(uint64_t *)&lock_arg[9];
    memcpy(pubkey_A, &lock_arg[17], BLAKE160_SIZE);
    memcpy(pubkey_B, &lock_arg[17 + BLAKE160_SIZE], BLAKE160_SIZE);
    return CKB_SUCCESS;
}

int verify_lock_attrs(uint8_t *input_lock_script, uint64_t input_len, uint8_t *output_lock_script, uint64_t output_len)
{
    mol_seg_t script_seg;
    script_seg.ptr = (uint8_t *)input_lock_script;
    script_seg.size = input_len;
    mol_seg_t input_code_hash = MolReader_Script_get_code_hash(&script_seg);
    if (input_code_hash.size != 32)
    {
        return ERROR_ENCODING;
    }
    mol_seg_t input_hash_type = MolReader_Script_get_hash_type(&script_seg);
    if (input_hash_type.ptr[0] != 0)
    {
        return ERROR_ENCODING;
    }

    script_seg.ptr = (uint8_t *)output_lock_script;
    script_seg.size = output_len;
    mol_seg_t output_code_hash = MolReader_Script_get_code_hash(&script_seg);
    if (input_code_hash.size != 32)
    {
        return ERROR_ENCODING;
    }
    mol_seg_t output_hash_type = MolReader_Script_get_hash_type(&script_seg);
    if (input_hash_type.ptr[0] != 0)
    {
        return ERROR_ENCODING;
    }

    if (memcmp(input_code_hash.ptr, output_code_hash.ptr, BLAKE2B_BLOCK_SIZE) != 0)
    {
        return ERROR_CODE_HASH_INCONSISTENT;
    }

    if (memcmp(input_hash_type.ptr, output_hash_type.ptr, 1) != 0)
    {
        return ERROR_HASH_TYPE_INCONSISTENT;
    }
    return CKB_SUCCESS;
}

int verify_sig_no_input(mol_seg_t lock_bytes_seg, uint8_t *input_pubkey, uint8_t *sig_verify, size_t end)
{
    unsigned char witness[MAX_WITNESS_SIZE];
    uint64_t witness_len = MAX_WITNESS_SIZE;
    int ret = ckb_load_witness(witness, &witness_len, 0, 0, CKB_SOURCE_GROUP_INPUT);
    // printf("123213      %lu", witness_len);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_SYSCALL;
    }
    if (witness_len > MAX_WITNESS_SIZE)
    {
        return ERROR_WITNESS_SIZE;
    }
    ret = extract_witness_lock(witness, witness_len, &lock_bytes_seg);
    if (ret != 0)
    {
        return ERROR_ENCODING;
    }

    if (lock_bytes_seg.size != 2 * SIGNATURE_SIZE + 9)
    {
        return ERROR_ARGUMENTS_LEN;
    }
    blake2b_state blake2b_ctx;
    blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
    //load all tx outputs.
    size_t i = 0;
    uint64_t len = 0;
    for (i = 0; i < end; i++)
    {
        unsigned char output[MAX_CELL];
        len = MAX_CELL;
        ret = ckb_load_cell(output, &len, 0, i, CKB_SOURCE_OUTPUT);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        if (len > MAX_CELL)
        {
            return ERROR_SYSCALL;
        }
        blake2b_update(&blake2b_ctx, output, len);
    }
    len = 0;
    // Clear lock field to zero, then digest the first witness
    memset((void *)(&lock_bytes_seg.ptr[9]), 0, 2 * SIGNATURE_SIZE);
    blake2b_update(&blake2b_ctx, (char *)&witness_len, sizeof(uint64_t));
    blake2b_update(&blake2b_ctx, witness, witness_len);

    uint8_t temp[MAX_WITNESS_SIZE];
    // Digest same group witnesses
    i = 1;
    while (1)
    {
        len = MAX_WITNESS_SIZE;
        ret = ckb_load_witness(temp, &len, 0, i, CKB_SOURCE_GROUP_INPUT);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (len > MAX_WITNESS_SIZE)
        {
            return ERROR_WITNESS_SIZE;
        }
        blake2b_update(&blake2b_ctx, (char *)&len, sizeof(uint64_t));
        blake2b_update(&blake2b_ctx, temp, len);
        i += 1;
    }
    // Digest witnesses that not covered by inputs
    i = ckb_calculate_inputs_len();
    while (1)
    {
        len = MAX_WITNESS_SIZE;
        ret = ckb_load_witness(temp, &len, 0, i, CKB_SOURCE_INPUT);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (len > MAX_WITNESS_SIZE)
        {
            return ERROR_WITNESS_SIZE;
        }
        blake2b_update(&blake2b_ctx, (char *)&len, sizeof(uint64_t));
        blake2b_update(&blake2b_ctx, temp, len);
        i += 1;
    }
    unsigned char message[BLAKE2B_BLOCK_SIZE];
    blake2b_final(&blake2b_ctx, message, BLAKE2B_BLOCK_SIZE);

    // Load signature
    secp256k1_context context;
    uint8_t secp_data[CKB_SECP256K1_DATA_SIZE];
    ret = ckb_secp256k1_custom_load_data(secp_data);
    if (ret != 0)
    {
        return ret;
    }
    ret = ckb_secp256k1_custom_verify_only_initialize(&context, secp_data);
    if (ret != 0)
    {
        return ret;
    }

    secp256k1_ecdsa_recoverable_signature signature;
    if (secp256k1_ecdsa_recoverable_signature_parse_compact(
            &context, &signature, sig_verify, sig_verify[RECID_INDEX]) == 0)
    {
        return ERROR_SECP_PARSE_SIGNATURE;
    }
    // Recover pubkey
    secp256k1_pubkey pubkey;
    if (secp256k1_ecdsa_recover(&context, &pubkey, &signature, message) != 1)
    {
        return ERROR_SECP_RECOVER_PUBKEY;
    }

    // Check pubkey hash
    size_t pubkey_size = PUBKEY_SIZE;
    if (secp256k1_ec_pubkey_serialize(&context, temp, &pubkey_size, &pubkey,
                                      SECP256K1_EC_COMPRESSED) != 1)
    {
        return ERROR_SECP_SERIALIZE_PUBKEY;
    }

    blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
    blake2b_update(&blake2b_ctx, temp, pubkey_size);
    blake2b_final(&blake2b_ctx, temp, BLAKE2B_BLOCK_SIZE);

    if (memcmp(input_pubkey, temp, BLAKE160_SIZE) != 0)
    {
        return ERROR_PUBKEY_BLAKE160_HASH;
    }
    return CKB_SUCCESS;
}

int verify_sig_all(mol_seg_t lock_bytes_seg, uint8_t *input_pubkey, uint8_t *sig_verify)
{
    unsigned char witness[MAX_WITNESS_SIZE];
    uint64_t witness_len = MAX_WITNESS_SIZE;
    int ret = ckb_load_witness(witness, &witness_len, 0, 0, CKB_SOURCE_GROUP_INPUT);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_SYSCALL;
    }
    if (witness_len > MAX_WITNESS_SIZE)
    {
        return ERROR_WITNESS_SIZE;
    }
    ret = extract_witness_lock(witness, witness_len, &lock_bytes_seg);
    if (ret != 0)
    {
        return ERROR_ENCODING;
    }

    if (lock_bytes_seg.size != 2 * SIGNATURE_SIZE + 9)
    {
        return ERROR_ARGUMENTS_LEN;
    }

    blake2b_state blake2b_ctx;
    blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
    //load tx hash.
    uint64_t len = 0;
    unsigned char tx_hash[BLAKE2B_BLOCK_SIZE];
    len = BLAKE2B_BLOCK_SIZE;
    ret = ckb_load_tx_hash(tx_hash, &len, 0);
    if (ret != CKB_SUCCESS)
    {
        return ret;
    }
    if (len != BLAKE2B_BLOCK_SIZE)
    {
        return ERROR_SYSCALL;
    }

    //digest tx hash.
    blake2b_update(&blake2b_ctx, tx_hash, BLAKE2B_BLOCK_SIZE);

    // Clear lock field to zero, then digest the first witness
    memset((void *)(&lock_bytes_seg.ptr[9]), 0, 2 * SIGNATURE_SIZE);
    blake2b_update(&blake2b_ctx, (char *)&witness_len, sizeof(uint64_t));
    blake2b_update(&blake2b_ctx, witness, witness_len);

    uint8_t temp[MAX_WITNESS_SIZE];
    // Digest same group witnesses
    size_t i = 1;
    while (1)
    {
        len = MAX_WITNESS_SIZE;
        ret = ckb_load_witness(temp, &len, 0, i, CKB_SOURCE_GROUP_INPUT);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (len > MAX_WITNESS_SIZE)
        {
            return ERROR_WITNESS_SIZE;
        }
        blake2b_update(&blake2b_ctx, (char *)&len, sizeof(uint64_t));
        blake2b_update(&blake2b_ctx, temp, len);
        i += 1;
    }
    // Digest witnesses that not covered by inputs
    i = ckb_calculate_inputs_len();
    while (1)
    {
        len = MAX_WITNESS_SIZE;
        ret = ckb_load_witness(temp, &len, 0, i, CKB_SOURCE_INPUT);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (len > MAX_WITNESS_SIZE)
        {
            return ERROR_WITNESS_SIZE;
        }
        blake2b_update(&blake2b_ctx, (char *)&len, sizeof(uint64_t));
        blake2b_update(&blake2b_ctx, temp, len);
        i += 1;
    }

    unsigned char message[BLAKE2B_BLOCK_SIZE];
    blake2b_final(&blake2b_ctx, message, BLAKE2B_BLOCK_SIZE);

    // Load signature
    secp256k1_context context;
    uint8_t secp_data[CKB_SECP256K1_DATA_SIZE];
    ret = ckb_secp256k1_custom_load_data(secp_data);
    if (ret != 0)
    {
        return ret;
    }
    ret = ckb_secp256k1_custom_verify_only_initialize(&context, secp_data);
    if (ret != 0)
    {
        return ret;
    }

    secp256k1_ecdsa_recoverable_signature signature;
    if (secp256k1_ecdsa_recoverable_signature_parse_compact(
            &context, &signature, sig_verify, sig_verify[RECID_INDEX]) == 0)
    {
        return ERROR_SECP_PARSE_SIGNATURE;
    }
    // Recover pubkey
    secp256k1_pubkey pubkey;
    if (secp256k1_ecdsa_recover(&context, &pubkey, &signature, message) != 1)
    {
        return ERROR_SECP_RECOVER_PUBKEY;
    }

    // Check pubkey hash
    size_t pubkey_size = PUBKEY_SIZE;
    if (secp256k1_ec_pubkey_serialize(&context, temp, &pubkey_size, &pubkey,
                                      SECP256K1_EC_COMPRESSED) != 1)
    {
        return ERROR_SECP_SERIALIZE_PUBKEY;
    }

    blake2b_init(&blake2b_ctx, BLAKE2B_BLOCK_SIZE);
    blake2b_update(&blake2b_ctx, temp, pubkey_size);
    blake2b_final(&blake2b_ctx, temp, BLAKE2B_BLOCK_SIZE);

    if (memcmp(input_pubkey, temp, BLAKE160_SIZE) != 0)
    {
        return ERROR_PUBKEY_BLAKE160_HASH;
    }
    return CKB_SUCCESS;
}

int printf_hex_string(unsigned char *str, int len)
{
    printf("\n\n\1232131312312321:    ");
    for (int i = 0; i < len; i++)
    {
        printf("%02x", str[i]);
    }
    return 0;
}

int main(int argc, char *argv[])
{
    // load the witness!!!

    unsigned char witness[MAX_WITNESS_SIZE];
    uint64_t witness_len = MAX_WITNESS_SIZE;
    int ret = ckb_load_witness(witness, &witness_len, 0, 0, CKB_SOURCE_GROUP_INPUT);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_SYSCALL;
    }
    if (witness_len > MAX_WITNESS_SIZE)
    {
        return ERROR_WITNESS_SIZE;
    }

    mol_seg_t lock_bytes_seg;
    ret = extract_witness_lock(witness, witness_len, &lock_bytes_seg);
    if (ret != 0)
    {
        return ERROR_ENCODING;
    }

    if (lock_bytes_seg.size != 2 * SIGNATURE_SIZE + 9)
    {
        return ERROR_ARGUMENTS_LEN;
    }

    uint8_t *gpc_witness = (uint8_t *)lock_bytes_seg.ptr;
    uint8_t flag = gpc_witness[0];
    uint64_t *nounce_witness = (uint64_t *)&gpc_witness[1];
    uint8_t sig_A[SIGNATURE_SIZE], sig_B[SIGNATURE_SIZE];
    memcpy(sig_A, &gpc_witness[9], SIGNATURE_SIZE);
    memcpy(sig_B, &gpc_witness[9 + SIGNATURE_SIZE], SIGNATURE_SIZE);

    // load the args about lock script in input.

    unsigned char input_lock_script[SCRIPT_SIZE];
    uint64_t input_script_len = SCRIPT_SIZE;
    ret = ckb_load_cell_by_field(input_lock_script, &input_script_len, 0, 0, CKB_SOURCE_INPUT, CKB_CELL_FIELD_LOCK);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_SYSCALL;
    }
    if (input_script_len > SCRIPT_SIZE)
    {
        return ERROR_SCRIPT_TOO_LONG;
    }
    uint8_t input_status = 0, input_pubkey_A[BLAKE160_SIZE], input_pubkey_B[BLAKE160_SIZE];
    uint64_t input_lock_time = 0, input_nounce = 0;
    ret = parse_lock_args(input_lock_script, input_script_len, &input_status,
                          &input_lock_time, &input_nounce, input_pubkey_A, input_pubkey_B);
    if (ret != CKB_SUCCESS)
    {
        return ERROR_ENCODING;
    }

    unsigned char input_type_script_hash[HASH_SIZE];
    uint64_t script_hash_len = HASH_SIZE;
    ret = ckb_load_cell_by_field(input_type_script_hash, &script_hash_len, 0, 0, CKB_SOURCE_INPUT, CKB_CELL_FIELD_TYPE_HASH);

    if (ret == 2)
    {
        for (int i = 0; i < HASH_SIZE; i++)
        {
            input_type_script_hash[i] = 0;
        }
    }
    else if (ret != CKB_SUCCESS)
    {
        return ret;
    }
    else if (script_hash_len != HASH_SIZE)
    {
        return ERROR_SYSCALL;
    }

    //verify the type script is same!!

    //Output: capacity (users check), lock (), type(checked).
    unsigned char output_type_script_hash[HASH_SIZE];
    script_hash_len = HASH_SIZE;
    size_t i = 0;
    while (1)
    {
        ret = ckb_load_cell_by_field(output_type_script_hash, &script_hash_len, 0, i, CKB_SOURCE_OUTPUT, CKB_CELL_FIELD_TYPE_HASH);
        if (ret == CKB_INDEX_OUT_OF_BOUND)
        {
            break;
        }
        if (ret == 2)
        {
            for (int i = 0; i < HASH_SIZE; i++)
            {
                output_type_script_hash[i] = 0;
            }
        }
        else if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        else if (script_hash_len != HASH_SIZE)
        {
            return ERROR_SYSCALL;
        }
        // printf_hex_string(output_type_script_hash, HASH_SIZE);
        if (memcmp(input_type_script_hash, output_type_script_hash, HASH_SIZE) != 0)
        {
            return ERROR_TYPE_SCRIPT_HASH_INCONSISTENT;
        }
        i++;
    }

    // four cases:

    if (input_status == 0 && flag == 0)
    {
        //verify the type scripts are same.
        ckb_debug("The good case!\n");

        // lets verify the signature is right (normal signature).
        ret = verify_sig_all(lock_bytes_seg, input_pubkey_A, sig_A);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        ret = verify_sig_all(lock_bytes_seg, input_pubkey_B, sig_B);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
    }
    else if ((input_status == 0 && flag == 1) || (input_status == 1 && flag == 1))
    {
        ckb_debug("The bad/ugly case, one party just want to close the channel!\n");
        // lets load the output lock arg!
        unsigned char output_lock_script[SCRIPT_SIZE];
        uint64_t output_script_len = SCRIPT_SIZE;
        ret = ckb_load_cell_by_field(output_lock_script, &output_script_len, 0, 0, CKB_SOURCE_OUTPUT, CKB_CELL_FIELD_LOCK);
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (output_script_len > SCRIPT_SIZE)
        {
            return ERROR_SCRIPT_TOO_LONG;
        }
        uint8_t output_status = 0, output_pubkey_A[BLAKE160_SIZE], output_pubkey_B[BLAKE160_SIZE];
        uint64_t output_lock_time = 0, output_nounce = 0;
        ret = parse_lock_args(output_lock_script, output_script_len, &output_status,
                              &output_lock_time, &output_nounce, output_pubkey_A, output_pubkey_B);
        if (output_nounce <= input_nounce && output_nounce != 0)
        {
            return ERROR_NOUNCE_INVALID;
        }
        if (output_status != 1)
        {
            return ERROR_STATUS_INVALID;
        }
        if ((memcmp(input_pubkey_A, output_pubkey_A, BLAKE160_SIZE) != 0) || (memcmp(input_pubkey_B, output_pubkey_B, BLAKE160_SIZE) != 0))
        {
            return ERROR_PUBKEY_INCONSISTENT;
        }
        // Verify the code hash and hash type is correct!
        ret = verify_lock_attrs(input_lock_script, input_script_len, output_lock_script, output_script_len);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        // Lets verify the signature (no-input signature).
        ret = verify_sig_no_input(lock_bytes_seg, input_pubkey_A, sig_A, 1);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        ret = verify_sig_no_input(lock_bytes_seg, input_pubkey_B, sig_B, 1);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
    }
    else if (input_status == 1 && flag == 0)
    {
        // check the since input.since == input.lock.arg.timeout.
        ckb_debug("The bad/ugly case, one party just want to settle this channel!\n");
        // lets get the since!.
        uint64_t input_since = 0, input_since_len = 8;
        ret = ckb_load_input_by_field(&input_since, &input_since_len, 0, 0,
                                      CKB_SOURCE_GROUP_INPUT, CKB_INPUT_FIELD_SINCE);
        if (ret != CKB_SUCCESS)
        {
            return ERROR_SYSCALL;
        }
        if (input_since != input_lock_time)
        {
            return ERROR_SINCE_INVALID;
        }
        if (input_nounce != *nounce_witness)
        {
            return ERROR_NOUNCE_INCONSISTENT;
        }
        // Lets verify the signature. (no-input signature.)
        ret = verify_sig_no_input(lock_bytes_seg, input_pubkey_A, sig_A, 2);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
        ret = verify_sig_no_input(lock_bytes_seg, input_pubkey_B, sig_B, 2);
        if (ret != CKB_SUCCESS)
        {
            return ret;
        }
    }
    else
    {
        return ERROR_FLAG_STATUS;
    }

    return CKB_SUCCESS;
}