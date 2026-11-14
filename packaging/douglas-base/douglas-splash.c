/* SPDX-License-Identifier: GPL-2.0-only
 *
 * douglas-splash: boot splash for the Fire HD 8 (douglas) Linux image.
 *
 * Draws the splash image with a progress bar on /dev/fb0 (simpledrm fbdev, XRGB8888) until
 * the compositor (kwin_wayland or phoc) takes the display. Progress follows OpenRC: services in
 * /run/openrc/started versus the services in the sysinit/boot/default runlevels.
 *
 * A tap on the screen or a volume key toggles a text view of the boot sequence (kernel log
 * from /dev/kmsg plus OpenRC service start events); another tap/press returns to the photo.
 *
 * Started first in the OpenRC sysinit runlevel by /etc/init.d/douglas-splash.
 */
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "font16x32.h"

/* raw 800x1280 XRGB8888; a picture of your own in /etc/douglas wins over the default */
#define CUSTOM_PHOTO "/etc/douglas/splash.bgrx"
#define PHOTO "/usr/share/douglas/splash.bgrx"
#define HOLD  "/run/douglas-splash.hold"
#define FW 16
#define FH 32

static uint8_t *fb;		/* mmap of /dev/fb0 */
static uint32_t *photo;		/* W*H pixels */
static int W, H, stride;	/* stride in bytes */

static void klog(const char *fmt, ...)
{
	char buf[256];
	int n = snprintf(buf, sizeof(buf), "<4>douglas-splash: ");
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf + n, sizeof(buf) - n, fmt, ap);
	va_end(ap);
	int fd = open("/dev/kmsg", O_WRONLY | O_CLOEXEC);
	if (fd >= 0) {
		write(fd, buf, strlen(buf));
		close(fd);
	}
}

/* ---------------------------------------------------------------- drawing */

static inline uint32_t *px(int x, int y) { return (uint32_t *)(fb + (size_t)y * stride) + x; }

static void fill(int x0, int y0, int w, int h, uint32_t c)
{
	for (int y = y0; y < y0 + h && y < H; y++)
		for (int x = x0; x < x0 + w && x < W; x++)
			*px(x, y) = c;
}

/* blend colour c over the photo (alpha 0..255) */
static void tint(int x0, int y0, int w, int h, uint32_t c, int a)
{
	for (int y = y0; y < y0 + h && y < H; y++)
		for (int x = x0; x < x0 + w && x < W; x++) {
			uint32_t p = photo ? photo[y * W + x] : 0;
			int r = (((p >> 16) & 255) * (255 - a) + ((c >> 16) & 255) * a) / 255;
			int g = (((p >> 8) & 255) * (255 - a) + ((c >> 8) & 255) * a) / 255;
			int b = ((p & 255) * (255 - a) + (c & 255) * a) / 255;
			*px(x, y) = (r << 16) | (g << 8) | b;
		}
}

static void restore_photo(int y0, int h)
{
	for (int y = y0; y < y0 + h && y < H; y++)
		if (photo)
			memcpy(px(0, y), &photo[y * W], W * 4);
		else
			memset(px(0, y), 0, W * 4);
}

static void glyph(int x, int y, unsigned char ch, uint32_t c)
{
	const unsigned char *g = &font16x32[ch * 64];
	for (int r = 0; r < FH; r++) {
		unsigned bits = (g[r * 2] << 8) | g[r * 2 + 1];
		for (int b = 0; b < FW; b++)
			if (bits & (0x8000 >> b) && x + b < W && y + r < H)
				*px(x + b, y + r) = c;
	}
}

static void text(int x, int y, const char *s, uint32_t c)
{
	for (; *s && x + FW <= W; s++, x += FW)
		glyph(x, y, (unsigned char)*s, c);
}

static void text_centered(int y, const char *s, uint32_t c)
{
	int n = strlen(s), maxc = W / FW;
	if (n > maxc)
		n = maxc;
	char buf[128];
	snprintf(buf, sizeof(buf), "%.*s", n, s);
	text((W - n * FW) / 2, y, buf, c);
}

/* ---------------------------------------------------------------- state */

#define BAR_Y   1040
#define BAR_X   100
#define BAR_W   600
#define BAR_H   12
#define STAT_Y  (BAR_Y - 56)
#define HINT_Y  1180

static double shown_pct, target_pct;
static char status[128] = "Starting Linux";
static int text_mode;

static void draw_splash_overlay(void)
{
	/* status line */
	restore_photo(STAT_Y, FH + 4);
	text_centered(STAT_Y, status, 0xffffff);
	/* bar: track + fill */
	restore_photo(BAR_Y - 4, BAR_H + 8);
	tint(BAR_X, BAR_Y, BAR_W, BAR_H, 0xffffff, 70);
	int fw = (int)(BAR_W * shown_pct / 100.0);
	fill(BAR_X, BAR_Y, fw, BAR_H, 0xffffff);
	/* hint */
	restore_photo(HINT_Y, FH + 4);
	text_centered(HINT_Y, "Tap or hold volume for details", 0xd0d0d0);
}

static void draw_splash_full(void)
{
	restore_photo(0, H);
	draw_splash_overlay();
}

/* ---------------------------------------------------------------- boot log (text view) */

#define MAXLINES 400
#define COLS 50
static char *lines[MAXLINES];
static int nlines, log_dirty;

static void add_line(uint32_t colour, const char *fmt, ...)
{
	char buf[1024];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	/* wrap into COLS-wide rows; first byte of each stored row encodes the colour class */
	size_t len = strlen(buf), off = 0;
	do {
		char row[COLS + 2];
		size_t n = len - off > COLS ? COLS : len - off;
		row[0] = colour == 0x80ff80 ? 'g' : colour == 0xffd060 ? 'y' : colour == 0xff8080 ? 'r' : 'w';
		memcpy(row + 1, buf + off, n);
		row[n + 1] = 0;
		if (nlines == MAXLINES) {
			free(lines[0]);
			memmove(lines, lines + 1, sizeof(lines[0]) * (MAXLINES - 1));
			nlines--;
		}
		lines[nlines++] = strdup(row);
		off += n;
	} while (off < len);
	log_dirty = 1;
}

static void draw_text_view(void)
{
	fill(0, 0, W, H, 0x000000);
	fill(0, 0, W, FH + 8, 0x203040);
	text(8, 4, "Boot details - tap to continue", 0xffffff);
	int rows = (H - FH - 12) / FH;
	int first = nlines > rows ? nlines - rows : 0;
	for (int i = first; i < nlines; i++) {
		uint32_t c = 0xe0e0e0;
		switch (lines[i][0]) {
		case 'g': c = 0x80ff80; break;
		case 'y': c = 0xffd060; break;
		case 'r': c = 0xff8080; break;
		}
		text(0, FH + 12 + (i - first) * FH, lines[i] + 1, c);
	}
	log_dirty = 0;
}

static int kmsg_fd = -1;

static void read_kmsg(void)
{
	char rec[2048];
	if (kmsg_fd < 0)
		kmsg_fd = open("/dev/kmsg", O_RDONLY | O_NONBLOCK);
	if (kmsg_fd < 0)
		return;
	for (;;) {
		ssize_t n = read(kmsg_fd, rec, sizeof(rec) - 1);
		if (n < 0) {
			if (errno == EPIPE)
				continue;	/* overwritten records: keep going */
			break;
		}
		rec[n] = 0;
		/* "prio,seq,usec,flags;message\n" */
		int prio = atoi(rec) & 7;
		unsigned long long usec = 0;
		char *p = strchr(rec, ',');
		if (p && (p = strchr(p + 1, ',')))
			usec = strtoull(p + 1, NULL, 10);
		char *msg = strchr(rec, ';');
		if (!msg)
			continue;
		msg++;
		char *nl = strchr(msg, '\n');
		if (nl)
			*nl = 0;
		if (strstr(msg, "DEBUG: Passed"))
			continue;	/* Wi-Fi driver chatter */
		add_line(prio <= 3 ? 0xff8080 : prio == 4 ? 0xffd060 : 0xe0e0e0,
			 "[%5llu.%02llu] %s", usec / 1000000, (usec / 10000) % 100, msg);
	}
}

/* ---------------------------------------------------------------- OpenRC progress */

#define MAXSVC 128
static char seen_started[MAXSVC][48], seen_starting[MAXSVC][48];
static int nstarted, nstarting;

static int in_list(char list[][48], int n, const char *s)
{
	for (int i = 0; i < n; i++)
		if (!strcmp(list[i], s))
			return 1;
	return 0;
}

static int count_runlevels(void)
{
	static const char *rl[] = { "/etc/runlevels/sysinit", "/etc/runlevels/boot", "/etc/runlevels/default" };
	char names[MAXSVC][48];
	int n = 0;
	for (unsigned i = 0; i < 3; i++) {
		DIR *d = opendir(rl[i]);
		struct dirent *e;
		if (!d)
			continue;
		while ((e = readdir(d)) && n < MAXSVC)
			if (e->d_name[0] != '.' && !in_list(names, n, e->d_name))
				snprintf(names[n++], 48, "%s", e->d_name);
		closedir(d);
	}
	return n;
}

static int poll_openrc(int total)
{
	DIR *d;
	struct dirent *e;
	int tinydm = 0;

	if ((d = opendir("/run/openrc/starting"))) {
		while ((e = readdir(d)))
			if (e->d_name[0] != '.') {
				snprintf(status, sizeof(status), "Starting %s", e->d_name);
				if (!in_list(seen_starting, nstarting, e->d_name) && nstarting < MAXSVC) {
					snprintf(seen_starting[nstarting++], 48, "%s", e->d_name);
					add_line(0xe0e0e0, " * Starting %s ...", e->d_name);
				}
			}
		closedir(d);
	}
	int started = 0;
	if ((d = opendir("/run/openrc/started"))) {
		while ((e = readdir(d)))
			if (e->d_name[0] != '.') {
				started++;
				if (!strcmp(e->d_name, "tinydm"))
					tinydm = 1;
				if (!in_list(seen_started, nstarted, e->d_name) && nstarted < MAXSVC) {
					snprintf(seen_started[nstarted++], 48, "%s", e->d_name);
					add_line(0x80ff80, " * %s started  [ ok ]", e->d_name);
				}
			}
		closedir(d);
	}
	if (started && total) {
		double p = 10.0 + 85.0 * started / total;
		if (p > 95.0)
			p = 95.0;
		if (p > target_pct)
			target_pct = p;
	}
	if (tinydm) {
		target_pct = 100.0;
		snprintf(status, sizeof(status), "Starting desktop");
	}
	return tinydm;
}

static int compositor_running(void)
{
	DIR *d = opendir("/proc");
	struct dirent *e;
	int found = 0;
	if (!d)
		return 0;
	while (!found && (e = readdir(d))) {
		char path[64], comm[32] = "";
		if (e->d_name[0] < '0' || e->d_name[0] > '9')
			continue;
		snprintf(path, sizeof(path), "/proc/%s/comm", e->d_name);
		FILE *f = fopen(path, "r");
		if (f) {
			if (fgets(comm, sizeof(comm), f) && (!strncmp(comm, "phoc", 4) || !strncmp(comm, "kwin_wayland", 12)))
				found = 1;
			fclose(f);
		}
	}
	closedir(d);
	return found;
}

/* ---------------------------------------------------------------- input */

#define MAXIN 16
static struct pollfd in[MAXIN];
static int nin;

static void scan_inputs(void)
{
	for (int i = 0; i < nin; i++)
		close(in[i].fd);
	nin = 0;
	DIR *d = opendir("/dev/input");
	struct dirent *e;
	if (!d)
		return;
	while ((e = readdir(d)) && nin < MAXIN)
		if (!strncmp(e->d_name, "event", 5)) {
			char p[64];
			snprintf(p, sizeof(p), "/dev/input/%s", e->d_name);
			int fd = open(p, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
			if (fd >= 0) {
				in[nin].fd = fd;
				in[nin].events = POLLIN;
				nin++;
			}
		}
	closedir(d);
}

static double now(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec + ts.tv_nsec / 1e9;
}

static double ignore_until, start_time;
static int want_details;
#define EARLY_WINDOW 6.0

/* returns 1 when a toggle gesture was seen */
static int read_inputs(int timeout_ms)
{
	static double last;
	int toggle = 0;
	if (!nin) {
		usleep(timeout_ms * 1000);
		return 0;
	}
	if (poll(in, nin, timeout_ms) <= 0)
		return 0;
	for (int i = 0; i < nin; i++) {
		struct input_event ev[32];
		ssize_t n;
		if (!(in[i].revents & POLLIN))
			continue;
		while ((n = read(in[i].fd, ev, sizeof(ev))) > 0)
			for (size_t k = 0; k < n / sizeof(ev[0]); k++) {
				if (ev[k].type != EV_KEY)
					continue;
				if (ev[k].code == KEY_VOLUMEUP || ev[k].code == KEY_VOLUMEDOWN) {
					/* the keypad re-reports a held key as release/press pairs: only a
					 * press after a full second of volume-key silence counts */
					static double last_vol;
					double t = now();
					if (ev[k].value == 1 && t - last_vol > 1.0)
						toggle = 1;
					/* early in boot any volume activity (even repeats of a key that
					 * was already held before we started listening) means "details" */
					if (ev[k].value && t - start_time < EARLY_WINDOW && !text_mode)
						want_details = 1;
					if (ev[k].value != 2)
						klog("input: key %d value %d (%.2f s since last)", ev[k].code,
						     ev[k].value, t - last_vol);
					last_vol = t;
				} else if (ev[k].code == BTN_TOUCH && ev[k].value == 1) {
					if (now() - start_time < 1.5) {
						klog("input: early touch ignored");
						continue;	/* ghost touch while the panel initialises */
					}
					klog("input: touch");
					toggle = 1;
				}
			}
	}
	if (toggle && (now() - last < 0.4 || now() < ignore_until)) {
		klog("input: toggle ignored (debounce)");
		toggle = 0;	/* debounce; also swallow the press that opened the view by holding */
	}
	if (toggle)
		last = now();
	return toggle;
}

/* is a volume key currently held down on any input device? */
static int volume_held(void)
{
	for (int i = 0; i < nin; i++) {
		unsigned long bits[KEY_MAX / (8 * sizeof(long)) + 1];
		memset(bits, 0, sizeof(bits));
		if (ioctl(in[i].fd, EVIOCGKEY(sizeof(bits)), bits) < 0)
			continue;
		for (int k = KEY_VOLUMEDOWN; k <= KEY_VOLUMEUP; k++)
			if (bits[k / (8 * sizeof(long))] & (1UL << (k % (8 * sizeof(long)))))
				return 1;
	}
	return 0;
}

/* While the details view is open the boot pauses before the desktop: the douglas-splash-hold
 * service (ordered before tinydm) waits as long as this file exists. */
static void set_text_mode(int on)
{
	text_mode = on;
	klog("%s boot details", on ? "showing" : "leaving");
	if (on) {
		int fd = open(HOLD, O_CREAT | O_WRONLY | O_CLOEXEC, 0644);
		if (fd >= 0)
			close(fd);
		draw_text_view();
	} else {
		unlink(HOLD);
		draw_splash_full();
	}
}

/* ---------------------------------------------------------------- main */

static int setup_fb(void)
{
	struct fb_var_screeninfo v;
	struct fb_fix_screeninfo f;
	int fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ioctl(fd, FBIOBLANK, FB_BLANK_UNBLANK);	/* makes the fbdev client modeset */
	if (ioctl(fd, FBIOGET_VSCREENINFO, &v) || ioctl(fd, FBIOGET_FSCREENINFO, &f) || v.bits_per_pixel != 32)
		return -1;
	W = v.xres;
	H = v.yres;
	stride = f.line_length;
	fb = mmap(NULL, f.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	return fb == MAP_FAILED ? -1 : 0;
}

static void load_photo(void)
{
	int fd = open(CUSTOM_PHOTO, O_RDONLY);
	if (fd < 0)
		fd = open(PHOTO, O_RDONLY);
	if (fd < 0)
		return;
	photo = malloc((size_t)W * H * 4);
	if (photo && read(fd, photo, (size_t)W * H * 4) != (ssize_t)W * H * 4) {
		free(photo);
		photo = NULL;
	}
	close(fd);
}

int main(void)
{
	setsid();
	signal(SIGHUP, SIG_IGN);
	signal(SIGPIPE, SIG_IGN);
	if (setup_fb()) {
		klog("framebuffer setup failed (errno %d)", errno);
		return 1;
	}
	load_photo();
	klog("fb %dx%d stride %d, photo %s", W, H, stride, photo ? "loaded" : "missing");
	draw_splash_full();

	add_line(0xffffff, "Fire HD 8 - Linux boot log");
	read_kmsg();

	double t0 = now(), last_scan = 0, done_at = 0;
	start_time = t0;
	int total = 0, held_checked = 0;
	target_pct = 5.0;

	for (;;) {
		double t = now();
		if (t - last_scan > 2.0) {
			scan_inputs();
			if (!total)
				total = count_runlevels();
			last_scan = t;
		}
		int finished = poll_openrc(total);
		read_kmsg();

		/* before OpenRC has /run: creep slowly so the bar is visibly alive */
		if (target_pct < 10.0)
			target_pct = 5.0 + (t - t0) * 0.5 > 10.0 ? 10.0 : 5.0 + (t - t0) * 0.5;
		double prev = shown_pct;
		shown_pct += (target_pct - shown_pct) * 0.25;
		if (target_pct - shown_pct < 0.2)
			shown_pct = target_pct;

		/* volume key held while booting: open the details view straight away */
		if (!held_checked && nin && volume_held()) {
			held_checked = 1;
			if (!text_mode)
				set_text_mode(1);
			ignore_until = now() + 2.0;
		}
		if (t - t0 > 6.0)
			held_checked = 1;

		int tog = read_inputs(100);
		if (want_details) {
			want_details = 0;
			held_checked = 1;
			if (!text_mode) {
				set_text_mode(1);
				ignore_until = now() + 2.0;
				tog = 0;
			}
		}
		if (tog) {
			set_text_mode(!text_mode);
		} else if (text_mode) {
			if (log_dirty)
				draw_text_view();
		} else if (shown_pct != prev || 1) {
			draw_splash_overlay();
		}

		if (finished && !done_at)
			done_at = t;
		/* stop once the compositor runs (it owns the display from then on), or after 20 s */
		if (done_at && (compositor_running() || t - done_at > 20.0)) {
			klog("handing over to the compositor after %.1f s", t - t0);
			break;
		}
		if (t - t0 > (text_mode ? 600.0 : 180.0))
			break;	/* safety: never outlive a stuck boot by much */
	}
	unlink(HOLD);
	klog("exit");
	return 0;
}
