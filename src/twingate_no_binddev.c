/*
 * twingate_no_binddev.c — LD_PRELOAD shim for twingated
 *
 * Intercepts setsockopt(SO_BINDTODEVICE) and silently ignores it, allowing
 * Twingate's relay sockets to follow normal Linux policy routing instead of
 * being forced onto the physical interface (wlp3s0).  When ProtonVPN is
 * active (ip rule 31545), relay traffic flows through the VPN tunnel,
 * bypassing restrictive work-network firewalls that block Twingate relay
 * ports (30000–31000).
 *
 * Compile:
 *   gcc -shared -fPIC -o /usr/local/lib/twingate-no-binddev.so \
 *       src/twingate_no_binddev.c -ldl
 *
 * Enable via systemd drop-in
 * (/etc/systemd/system/twingate.service.d/no-bindtodevice.conf):
 *   [Service]
 *   Environment=LD_PRELOAD=/usr/local/lib/twingate-no-binddev.so
 *
 * Use split_tunnel.sh twingate-proxy [on|off] to manage the drop-in.
 */

#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <sys/socket.h>

typedef int (*real_setsockopt_t)(int, int, int, const void *, socklen_t);

int setsockopt(int sockfd, int level, int optname,
               const void *optval, socklen_t optlen)
{
    static real_setsockopt_t real_fn = NULL;
    if (!real_fn)
        real_fn = (real_setsockopt_t)dlsym(RTLD_NEXT, "setsockopt");

    /*
     * Silently drop SO_BINDTODEVICE so that Twingate relay connections
     * use policy routing (ProtonVPN) rather than being pinned to the
     * physical interface.
     */
    if (level == SOL_SOCKET && optname == SO_BINDTODEVICE)
        return 0;

    return real_fn(sockfd, level, optname, optval, optlen);
}
