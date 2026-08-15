#include "interface_deps/vendor_pump_headers_st/vendor_pump.h"

// Native impl of Pump for the LOCAL test build only -- stands in for
// the vendor's real runtime, which the remote plc side of the
// deployment provides. plc emits only an extern declaration for Pump
// (its FUNCTION_BLOCK is {external} in vendor_pump.st); this
// definition supplies the actual body that main_program invokes via
// Plant.
void Pump(Pump_type *self) { self->rOut = self->rIn * 2.0f; }
