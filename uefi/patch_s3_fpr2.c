/* SPDX-License-Identifier: MIT
 * Copyright (c) 2026 Arla
 *
 * HP F.24 pre-ExitBootServices S3 boot-script patcher.
 *
 * This is deliberately freestanding: no CRT, no allocations, no filesystem
 * writes, no flash access.  It reads AcpiGlobalVariable, validates the live
 * PI/MDE boot-script structure and the required structured target fields,
 * then changes one volatile RAM byte in a volatile boot-script entry.
 */

#include <stdint.h>
#include <stddef.h>

#if defined(__clang__) || defined(__GNUC__)
#define EFIAPI __attribute__((ms_abi))
#else
#define EFIAPI
#endif

typedef uint64_t EFI_STATUS;
typedef void *EFI_HANDLE;
typedef uint64_t UINTN;
typedef uint16_t CHAR16;

#define EFI_SUCCESS               ((EFI_STATUS)0)
#define EFI_LOAD_ERROR            ((EFI_STATUS)0x8000000000000001ULL)
#define EFI_INVALID_PARAMETER     ((EFI_STATUS)0x8000000000000002ULL)
#define EFI_UNSUPPORTED           ((EFI_STATUS)0x8000000000000003ULL)
#define EFI_NOT_FOUND             ((EFI_STATUS)0x800000000000000EULL)
#define EFI_COMPROMISED_DATA      ((EFI_STATUS)0x8000000000000021ULL)
#define EFI_ERROR(Status)         (((Status) & 0x8000000000000000ULL) != 0)

typedef struct {
    uint64_t Signature;
    uint32_t Revision;
    uint32_t HeaderSize;
    uint32_t CRC32;
    uint32_t Reserved;
} EFI_TABLE_HEADER;

typedef struct {
    uint32_t Data1;
    uint16_t Data2;
    uint16_t Data3;
    uint8_t Data4[8];
} EFI_GUID;

struct EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;
typedef EFI_STATUS (EFIAPI *EFI_TEXT_STRING)(
    struct EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *This,
    CHAR16 *String
);

typedef struct EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL {
    void *Reset;
    EFI_TEXT_STRING OutputString;
    void *TestString;
    void *QueryMode;
    void *SetMode;
    void *SetAttribute;
    void *ClearScreen;
    void *SetCursorPosition;
    void *EnableCursor;
    void *Mode;
} EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL;

typedef EFI_STATUS (EFIAPI *EFI_GET_VARIABLE)(
    CHAR16 *VariableName,
    EFI_GUID *VendorGuid,
    uint32_t *Attributes,
    UINTN *DataSize,
    void *Data
);

typedef struct {
    EFI_TABLE_HEADER Hdr;
    void *GetTime;
    void *SetTime;
    void *GetWakeupTime;
    void *SetWakeupTime;
    void *SetVirtualAddressMap;
    void *ConvertPointer;
    EFI_GET_VARIABLE GetVariable;
} EFI_RUNTIME_SERVICES_MIN;

typedef struct {
    EFI_TABLE_HEADER Hdr;
    CHAR16 *FirmwareVendor;
    uint32_t FirmwareRevision;
    uint32_t Pad;
    EFI_HANDLE ConsoleInHandle;
    void *ConIn;
    EFI_HANDLE ConsoleOutHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *ConOut;
    EFI_HANDLE StandardErrorHandle;
    EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *StdErr;
    EFI_RUNTIME_SERVICES_MIN *RuntimeServices;
    void *BootServices;
    UINTN NumberOfTableEntries;
    void *ConfigurationTable;
} EFI_SYSTEM_TABLE_MIN;

static EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL *gConOut;

static const EFI_GUID kAcpiGlobalVariableGuid = {
    0xAF9FFD67U, 0xEC10U, 0x488AU,
    {0x9D, 0xFC, 0x6C, 0xBF, 0x5E, 0xE2, 0x2C, 0x2E}
};

static CHAR16 kAcpiGlobalVariableName[] = {
    'A','c','p','i','G','l','o','b','a','l','V','a','r','i','a','b','l','e',0
};

enum {
    SCRIPT_SCAN_LIMIT = 0x20000,
    TARGET_BYTE_IN_ENTRY = 0x10,
    TARGET_ENTRY_LENGTH = 0x24,
    MAX_ENTRY_LENGTH = 0x1000,
    MAX_ENTRY_COUNT = 4096
};

static void print_ascii(const char *text) {
    CHAR16 buffer[96];
    UINTN used = 0;

    if (gConOut == NULL || gConOut->OutputString == NULL) {
        return;
    }

    while (*text != 0) {
        buffer[used++] = (CHAR16)(uint8_t)*text++;
        if (used == (sizeof(buffer) / sizeof(buffer[0])) - 1) {
            buffer[used] = 0;
            gConOut->OutputString(gConOut, buffer);
            used = 0;
        }
    }
    if (used != 0) {
        buffer[used] = 0;
        gConOut->OutputString(gConOut, buffer);
    }
}

static void print_hex64(uint64_t value) {
    static const char digits[] = "0123456789ABCDEF";
    CHAR16 buffer[19];
    unsigned i;

    buffer[0] = '0';
    buffer[1] = 'x';
    for (i = 0; i < 16; ++i) {
        buffer[2 + i] = (CHAR16)digits[(value >> ((15U - i) * 4U)) & 0xFU];
    }
    buffer[18] = 0;
    gConOut->OutputString(gConOut, buffer);
}

static void print_value(const char *label, uint64_t value) {
    print_ascii(label);
    print_hex64(value);
    print_ascii("\r\n");
}

static uint32_t read_u32(volatile const uint8_t *p) {
    return ((uint32_t)p[0]) |
           ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) |
           ((uint32_t)p[3] << 24);
}

static uint64_t read_u64(volatile const uint8_t *p) {
    return ((uint64_t)read_u32(p)) | ((uint64_t)read_u32(p + 4) << 32);
}

static int target_entry_fields_match(volatile const uint8_t *entry, int allow_patched) {
    uint64_t expected_address = 0x00000000FE010000ULL |
        (allow_patched ? 0x8CULL : 0x0CULL);

    /* Validate the documented PI/MDE MEM_WRITE32 entry fields rather than
       retaining a literal vendor boot-script byte sequence.  The parser
       separately establishes that this is a real entry boundary. */
    if (read_u32(entry + 4U) != TARGET_ENTRY_LENGTH ||
        entry[8U] != 0x02U || entry[9U] != 0x02U ||
        entry[10U] != 0U || entry[11U] != 0U ||
        entry[12U] != 0U || entry[13U] != 0U ||
        entry[14U] != 0U || entry[15U] != 0U ||
        read_u64(entry + 16U) != expected_address ||
        read_u64(entry + 24U) != 1U ||
        read_u32(entry + 32U) != 0U) {
        return 0;
    }
    return 1;
}

static EFI_STATUS validate_script(
    volatile const uint8_t *script,
    uint64_t *terminate_offset,
    uint64_t *entry_count,
    uint64_t *target_entry_offset
) {
    uint32_t offset = 0;
    uint32_t count = 0;
    uint32_t target_count = 0;
    uint32_t found_target_offset = 0;

    while (offset + 9U <= SCRIPT_SCAN_LIMIT && count < MAX_ENTRY_COUNT) {
        uint8_t opcode = script[offset + 8U];
        uint32_t length;

        if (opcode == 0xFFU) {
            if (target_count != 1U) {
                return EFI_COMPROMISED_DATA;
            }
            *terminate_offset = offset;
            *entry_count = count;
            *target_entry_offset = found_target_offset;
            return EFI_SUCCESS;
        }

        length = read_u32(script + offset + 4U);
        if (length < 9U || length > MAX_ENTRY_LENGTH) {
            return EFI_COMPROMISED_DATA;
        }
        if (offset > SCRIPT_SCAN_LIMIT - length) {
            return EFI_COMPROMISED_DATA;
        }
        if (length == TARGET_ENTRY_LENGTH &&
            (target_entry_fields_match(script + offset, 0) ||
             target_entry_fields_match(script + offset, 1))) {
            found_target_offset = offset;
            ++target_count;
        }
        offset += length;
        ++count;
    }
    return EFI_COMPROMISED_DATA;
}

EFI_STATUS EFIAPI EfiMain(EFI_HANDLE ImageHandle, EFI_SYSTEM_TABLE_MIN *SystemTable) {
    EFI_STATUS status;
    uint32_t attributes = 0;
    UINTN data_size = sizeof(uint64_t);
    uint64_t acpi_variable_set_address = 0;
    uint64_t script_address;
    uint64_t terminate_offset = 0;
    uint64_t entry_count = 0;
    uint64_t target_entry_offset = 0;
    volatile uint8_t *acpi_variable_set;
    volatile uint8_t *script;
    volatile uint8_t *target;
    int original_matches;
    int patched_matches;

    (void)ImageHandle;
    if (SystemTable == NULL || SystemTable->ConOut == NULL ||
        SystemTable->RuntimeServices == NULL ||
        SystemTable->RuntimeServices->GetVariable == NULL) {
        return EFI_INVALID_PARAMETER;
    }
    gConOut = SystemTable->ConOut;

    print_ascii("HP pre-EBS S3 FPR2 patcher v1\r\n");
    print_ascii("Read/validate volatile RAM only; no flash access.\r\n");

    status = SystemTable->RuntimeServices->GetVariable(
        kAcpiGlobalVariableName,
        (EFI_GUID *)&kAcpiGlobalVariableGuid,
        &attributes,
        &data_size,
        &acpi_variable_set_address
    );
    if (EFI_ERROR(status)) {
        print_value("ERROR GetVariable status=", status);
        return status;
    }
    print_value("Variable data size=", data_size);
    print_value("AcpiVariableSet=", acpi_variable_set_address);

    if ((data_size != 4U && data_size != 8U) ||
        acpi_variable_set_address < 0x100000ULL ||
        acpi_variable_set_address >= 0x100000000ULL ||
        (acpi_variable_set_address & 0xFFFULL) != 0) {
        print_ascii("ERROR implausible AcpiVariableSet pointer/size.\r\n");
        return EFI_COMPROMISED_DATA;
    }

    acpi_variable_set = (volatile uint8_t *)(uintptr_t)acpi_variable_set_address;
    script_address = read_u64(acpi_variable_set + 0x18U);
    print_value("BootScript=", script_address);
    if (script_address < 0x100000ULL ||
        script_address >= 0x100000000ULL ||
        (script_address & 0xFFFULL) != 0 ||
        script_address > 0x100000000ULL - SCRIPT_SCAN_LIMIT) {
        print_ascii("ERROR implausible boot-script pointer.\r\n");
        return EFI_COMPROMISED_DATA;
    }

    script = (volatile uint8_t *)(uintptr_t)script_address;
    status = validate_script(
        script, &terminate_offset, &entry_count, &target_entry_offset
    );
    if (EFI_ERROR(status)) {
        print_ascii("ERROR malformed boot-script structure/terminate.\r\n");
        return status;
    }
    print_value("Entry count=", entry_count);
    print_value("Terminate offset=", terminate_offset);
    print_value("Target entry offset=", target_entry_offset);

    original_matches = target_entry_fields_match(script + target_entry_offset, 0);
    patched_matches = target_entry_fields_match(script + target_entry_offset, 1);
    target = script + target_entry_offset + TARGET_BYTE_IN_ENTRY;
    print_value(
        "Target physical=",
        script_address + target_entry_offset + TARGET_BYTE_IN_ENTRY
    );
    print_value("Target pre-byte=", (uint64_t)*target);

    if (!original_matches && !patched_matches) {
        print_ascii("ERROR target entry fields did not validate; NOTHING CHANGED.\r\n");
        return EFI_COMPROMISED_DATA;
    }
    if (patched_matches) {
        print_ascii("ALREADY PATCHED and target entry fields validate.\r\n");
        return EFI_SUCCESS;
    }

    *target = 0x8CU;
#if defined(__clang__) || defined(__GNUC__)
    __asm__ __volatile__("mfence" ::: "memory");
#endif

    print_value("Target post-byte=", (uint64_t)*target);
    if (!target_entry_fields_match(script + target_entry_offset, 1)) {
        print_ascii("ERROR post-write verification failed.\r\n");
        return EFI_LOAD_ERROR;
    }

    print_ascii("SUCCESS: FE01000C -> FE01008C in volatile pre-EBS script.\r\n");
    print_ascii("Start Windows WITHOUT reboot so D6 snapshots this copy.\r\n");
    return EFI_SUCCESS;
}
