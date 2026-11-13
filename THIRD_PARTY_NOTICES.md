# Third-party notices

`Vendor/CSSH.xcframework` contains prebuilt static libraries from
[DimaRU/Libssh2Prebuild](https://github.com/DimaRU/Libssh2Prebuild):

- **libssh2 1.11.0**, BSD 3-Clause license. See <https://github.com/libssh2/libssh2/blob/libssh2-1.11.0/COPYING>.
- **OpenSSL 1.1.1w**, dual OpenSSL / SSLeay license. See <https://www.openssl.org/source/license-openssl-ssleay.txt>.
  This product includes software developed by the OpenSSL Project for use in the OpenSSL Toolkit
  (http://www.openssl.org/). This product includes cryptographic software written by Eric Young
  (eay@cryptsoft.com).

OpenSSL 1.1.1 reached end of life in September 2023 and no longer gets public security fixes.
hpg only uses it for SSH to a single host you choose, but keep that in mind.
