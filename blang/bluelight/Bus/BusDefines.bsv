// Original version from https://github.com/B-Lang-org/bsc-contrib
// Copyright (c) 2020 Bluespec, Inc. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
// Modified for use in BlueLight by Kamyar Mohajerani

package BusDefines;

import Arbiter     :: *;
import Connectable :: *;
import FIFO        :: *;

typedef struct {
    Bool last;  // last word of the type
    w__  data;  // data word
} WithLast#(type w__)  deriving (Bits, Eq, FShow);

interface BusSender#(type a);
   interface FIFO#(a)    in;
   interface BusSend#(a) out;
endinterface

interface BusSenderWL#(type a);
   interface FIFO#(WithLast#(a)) in;
   interface BusSendWL#(a)      out;
endinterface

interface BusReceiver#(type a);
   interface BusRecv#(a) in;
   interface FIFO#(a)    out;
endinterface

(* always_ready, always_enabled *)
interface BusSend#(type a);
  method a  data;
  method Bool valid;
  (* prefix="" *)
  method Action ready((* port="ready" *) Bool value);
endinterface

(* always_ready, always_enabled *)
interface BusSendWL#(type a);
  method a     data;
  method Bool  last;
  method Bool valid;
  (* prefix="" *)
  method Action ready((* port="ready" *) Bool value);
endinterface

(* always_ready, always_enabled *)
interface BusRecv#(type a);
  (* prefix="" *)
  method Action data((* port="data" *) a value);
  (* prefix="" *)
  method Action valid((* port="valid" *) Bool value);
  method Bool ready;
endinterface

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

instance Connectable#( BusSend#(td), BusRecv#(td) );
   module mkConnection#( BusSend#(td) m, BusRecv#(td) s )(Empty);
      (* fire_when_enabled, no_implicit_conditions *)
      rule connect1; s.data(  m.data() )  ; endrule
      rule connect2; s.valid( m.valid() ) ; endrule
      rule connect3; m.ready( s.ready() ) ; endrule
   endmodule
endinstance

////////////////////////////////////////////////////////////////////////////////
///
////////////////////////////////////////////////////////////////////////////////

typeclass BusPayload#(type a, type b) dependencies(a determines b);
   function Bool isLast (a payload);
   function b getId(a payload);
   function a setId(a payload, b id);
endtypeclass


instance Arbitable#(BusSend#(a));
   module mkArbiterRequest#(BusSend#(a) bus_send) (ArbiterRequest_IFC);
      
      method Bool request;
	 return bus_send.valid;
      endmethod
      method Bool lock;
	 return False;
      endmethod
      method Action grant;
	 // a noop
      endmethod

   endmodule
endinstance


endpackage
