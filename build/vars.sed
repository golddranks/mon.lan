# Non-secret values substituted into every file under image/<device>/ at build
# time, in the same sed pass as secrets.sed (which stays out of git). A value
# belongs here if it is arbitrary - an address, a prefix, an opaque id - and
# appears more than once; names somebody chose stay literal. build.sh refuses to
# ship an image while any @TOKEN@ is left.

# The ULA prefix: hand-picked (fd42 + "mon" + 00), not RFC 4193-derived.
s|@ULA@|fd42:6d6f:6e00|g


# The 802.11r mobility domain. The value means nothing by itself - it only has to
# be identical on every AP, or fast roaming stops working without an error.
s|@FT_MDID@|cc66|g
