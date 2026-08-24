/* reboot helper for MSM8916: reboot into bootloader (fastboot) or EDL.
 *
 * Vendor (Android-based) kernels pass the reboot reason to the msm_restart
 * driver via the reboot(2) syscall using LINUX_REBOOT_CMD_RESTART2 with a
 * mode string. Mainline kernels use the reboot-mode sysfs instead. This
 * helper tries both, falling back to a plain reboot.
 */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/reboot.h>
#include <linux/reboot.h>

static void set_reboot_mode(const char *mode)
{
	char path[64];
	FILE *f;

	snprintf(path, sizeof(path), "/sys/reboot-mode/%s", mode);
	if (access(path, W_OK) == 0) {
		f = fopen(path, "w");
		if (f) {
			fputc('1', f);
			fclose(f);
			return;
		}
	}
	if (access("/sys/power/reboot_reason", W_OK) == 0) {
		f = fopen("/sys/power/reboot_reason", "w");
		if (f) {
			fputs(mode, f);
			fclose(f);
			return;
		}
	}
	/* vendor kernel: pass the reboot reason via reboot(2) RESTART2 */
	reboot(LINUX_REBOOT_CMD_RESTART2, mode);
}

int main(int argc, char **argv)
{
	const char *mode = NULL;

	if (argc > 1) {
		if (!strcmp(argv[1], "bootloader") || !strcmp(argv[1], "fastboot"))
			mode = "bootloader";
		else if (!strcmp(argv[1], "edl") || !strcmp(argv[1], "dload"))
			mode = "edl";
	}
	if (mode)
		set_reboot_mode(mode);
	reboot(RB_AUTOBOOT);
	return 0;
}
