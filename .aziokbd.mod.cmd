savedcmd_aziokbd.mod := printf '%s\n'   aziokbd.o | awk '!x[$$0]++ { print("./"$$0) }' > aziokbd.mod
