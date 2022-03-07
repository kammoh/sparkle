# Package: LWC_config 

- **File**: LWC_config.vhd
## Constants

| Name       | Type     | Value      | Description                                                                                                                   |
| ---------- | -------- | ---------- | ----------------------------------------------------------------------------------------------------------------------------- |
| W          | positive | 32         |                                                                                                                               |
| SW         | positive | W          | currently only W=SW is supported                                                                                              |
| PDI_SHARES | positive | 1          | Change the default value ONLY in a masked implementation  Number of PDI shares, 1 for a non-masked implementation             |
| SDI_SHARES | positive | PDI_SHARES | Number of SDI shares, 1 for a non-masked implementation  Does not need to be the same as PDI_SHARES but this is the default   |
| RW         | natural  | 0          | Width of RDI port in bits. Set to 0 if not used.                                                                              |
| ASYNC_RSTN | boolean  | False      | Assume an asynchronous and active-low reset.  Can be set to `True` given that support for it is implemented in the CryptoCore |
