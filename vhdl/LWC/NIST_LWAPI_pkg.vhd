--===============================================================================================--
--! @file       NIST_LWAPI_pkg.vhd 
--! @brief      NIST lightweight API package
--! @author     Panasayya Yalla & Ekawat (ice) Homsirikamol
--! @author     Kamyar Mohajerani
--! @copyright  Copyright (c) 2022 Cryptographic Engineering Research Group
--!             ECE Department, George Mason University Fairfax, VA, U.S.A.
--!             All rights Reserved.
--! @license    This project is released under the GNU Public License.
--!             The license and distribution terms for this file may be
--!             found in the file LICENSE in this distribution or at
--!             http://www.gnu.org/licenses/gpl-3.0.txt
--! @note       This is publicly available encryption source code that falls
--!             under the License Exception TSU (Technology and software-
--!             unrestricted)
---------------------------------------------------------------------------------------------------
--!
--!
--!                        DO NOT CHANGE ANYTHING ON THIS FILE!
--!
--!             User-configurable constants have moved to the `LWC_config` package
--!             All the changes to configuration are applied in `LWC_config`
--!
--!             As before, the package constants are available from this package (`NIST_LWAPI_pkg`)
--!               and can be made visible in the design via a 'use' clause. For example:
--!               
--!                  use work.NIST_LWAPI_pkg.all;
--!                  report "W times PDI_SHARES is " & integer'image(W*PDI_SHARES);
--!
--!
--!
--===============================================================================================--

library IEEE;
use IEEE.STD_LOGIC_1164.all;

use work.LWC_config;

package NIST_LWAPI_pkg is

    --===========================================================================================--
    --=                        DO NOT CHANGE ANYTHING ON THIS FILE!                             =--
    --===========================================================================================--

    --======================================== Constants ========================================--
    subtype T_LWC_SEGMENT is std_logic_vector(3 downto 0);
    subtype T_LWC_OPCODE is std_logic_vector(3 downto 0);

    --======================================== Constants ========================================--

    --! **** DO NOT CHANGE ANY OF THE CONSTANT VALUES HERE! *****
    --! to set design-specific values for these parameters, create LWC_config package file
    --! Please see 'LWC_config_template.vhd' for a functional template.
    --! Also examples for different LWC_config files are provided in the dummy_lwc directory
    --!
    --! External bus: supported values are 8, 16 and 32 bits
    constant W          : natural  := LWC_config.W;
    --! currently only W=SW is supported
    constant SW         : natural  := LWC_config.SW;
    --! Applicable only to protected implementations
    --! For unprotected implementations they are set to the default values of 
    --!     PDI_SHARES=SDI_SHARES=1, RW=0
    constant PDI_SHARES : positive := LWC_config.PDI_SHARES;
    constant SDI_SHARES : positive := LWC_config.SDI_SHARES;
    constant RW         : natural  := LWC_config.RW;
    --! Asynchronous and active-low reset.
    constant ASYNC_RSTN : boolean  := LWC_config.ASYNC_RSTN;

    constant Wdiv8  : natural;
    constant SWdiv8 : natural;

    --! INSTRUCTIONS (OPCODES)
    constant INST_HASH      : T_LWC_OPCODE;
    constant INST_ENC       : T_LWC_OPCODE;
    constant INST_DEC       : T_LWC_OPCODE;
    constant INST_LDKEY     : T_LWC_OPCODE;
    constant INST_ACTKEY    : T_LWC_OPCODE;
    constant INST_SUCCESS   : T_LWC_OPCODE;
    constant INST_FAILURE   : T_LWC_OPCODE;
    --! SEGMENT TYPE ENCODING
    --! Reserved := "0000";
    constant HDR_AD         : T_LWC_SEGMENT;
    constant HDR_NPUB_AD    : T_LWC_SEGMENT;
    constant HDR_AD_NPUB    : T_LWC_SEGMENT;
    constant HDR_PT         : T_LWC_SEGMENT;
    constant HDR_CT         : T_LWC_SEGMENT;
    constant HDR_CT_TAG     : T_LWC_SEGMENT;
    constant HDR_HASH_MSG   : T_LWC_SEGMENT;
    constant HDR_TAG        : T_LWC_SEGMENT;
    constant HDR_HASH_VALUE : T_LWC_SEGMENT;
    constant HDR_LENGTH     : T_LWC_SEGMENT;
    constant HDR_KEY        : T_LWC_SEGMENT;
    constant HDR_NPUB       : T_LWC_SEGMENT;
    --! Reserved := "1011";
    --NOT USED in NIST LWC
    constant HDR_NSEC       : T_LWC_SEGMENT;
    --NOT USED in NIST LWC
    constant HDR_ENSEC      : T_LWC_SEGMENT;

end package;

package body NIST_LWAPI_pkg is
    constant Wdiv8  : natural := W / 8;
    constant SWdiv8 : natural := SW / 8;

    --! INSTRUCTIONS (OPCODES)
    constant INST_HASH      : T_LWC_OPCODE  := "1000";
    constant INST_ENC       : T_LWC_OPCODE  := "0010";
    constant INST_DEC       : T_LWC_OPCODE  := "0011";
    constant INST_LDKEY     : T_LWC_OPCODE  := "0100";
    constant INST_ACTKEY    : T_LWC_OPCODE  := "0111";
    constant INST_SUCCESS   : T_LWC_OPCODE  := "1110";
    constant INST_FAILURE   : T_LWC_OPCODE  := "1111";
    --! SEGMENT TYPE ENCODING
    --! Reserved := "0000";
    constant HDR_AD         : T_LWC_SEGMENT := "0001";
    constant HDR_NPUB_AD    : T_LWC_SEGMENT := "0010";
    constant HDR_AD_NPUB    : T_LWC_SEGMENT := "0011";
    constant HDR_PT         : T_LWC_SEGMENT := "0100";
    constant HDR_CT         : T_LWC_SEGMENT := "0101";
    constant HDR_CT_TAG     : T_LWC_SEGMENT := "0110";
    constant HDR_HASH_MSG   : T_LWC_SEGMENT := "0111";
    constant HDR_TAG        : T_LWC_SEGMENT := "1000";
    constant HDR_HASH_VALUE : T_LWC_SEGMENT := "1001";
    constant HDR_LENGTH     : T_LWC_SEGMENT := "1010";
    constant HDR_KEY        : T_LWC_SEGMENT := "1100";
    constant HDR_NPUB       : T_LWC_SEGMENT := "1101";
    --! Reserved := "1011";
    --NOT USED in NIST LWC
    constant HDR_NSEC       : T_LWC_SEGMENT := "1110";
    --NOT USED in NIST LWC
    constant HDR_ENSEC      : T_LWC_SEGMENT := "1111";
end package body;
