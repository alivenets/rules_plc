// ---------------------------------------------------- //
// This file is auto-generated                          //
// Manual changes made to this file will be overwritten //
// ---------------------------------------------------- //

#ifndef _HOME_ALEXANDER_PROJECTS_RULES_PLC_HEADERS_HELLO_H_
#define _HOME_ALEXANDER_PROJECTS_RULES_PLC_HEADERS_HELLO_H_

#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include <time.h>
#include <dependencies.plc.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t x;
} hello_type;

extern hello_type hello_instance;

void hello(hello_type* self);

#ifdef __cplusplus
}
#endif /* __cplusplus */

#endif /* !_HOME_ALEXANDER_PROJECTS_RULES_PLC_HEADERS_HELLO_H_ */
