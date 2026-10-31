/*
 * Stand-in for Windows' system icuuc.dll (System32, Windows 10 1903+), which
 * Wine doesn't ship. The ESCargot Windows build's static QtCore imports the
 * ucnv_* converter API from it for codecs Qt has no built-in support for.
 *
 * Every converter open fails, so Qt treats those encodings as unavailable and
 * keeps using its built-in UTF-8/UTF-16/UTF-32/Latin-1 converters. The rest are
 * only reachable through a converter ucnv_open handed out, so they do nothing.
 */
#include <stdint.h>

#define U_FILE_ACCESS_ERROR 4

typedef int32_t UErrorCode;

__declspec(dllexport) void *ucnv_open(const char *name, UErrorCode *err)
{
    (void)name;
    if (err && *err <= 0)
        *err = U_FILE_ACCESS_ERROR;
    return 0;
}

__declspec(dllexport) int32_t ucnv_countAvailable(void) { return 0; }
__declspec(dllexport) const char *ucnv_getAvailableName(int32_t n) { (void)n; return 0; }
__declspec(dllexport) const char *ucnv_getStandardName(const char *name, const char *standard, UErrorCode *err)
{
    (void)name; (void)standard;
    if (err && *err <= 0)
        *err = U_FILE_ACCESS_ERROR;
    return 0;
}

#define STUB(fn) __declspec(dllexport) intptr_t fn(void) { return 0; }
STUB(UCNV_FROM_U_CALLBACK_SUBSTITUTE)
STUB(UCNV_TO_U_CALLBACK_SUBSTITUTE)
STUB(ucnv_cbFromUWriteUChars)
STUB(ucnv_cbToUWriteUChars)
STUB(ucnv_close)
STUB(ucnv_fromUCountPending)
STUB(ucnv_fromUnicode)
STUB(ucnv_getFromUCallBack)
STUB(ucnv_getMaxCharSize)
STUB(ucnv_getName)
STUB(ucnv_getToUCallBack)
STUB(ucnv_reset)
STUB(ucnv_setFromUCallBack)
STUB(ucnv_setToUCallBack)
STUB(ucnv_toUCountPending)
STUB(ucnv_toUnicode)
