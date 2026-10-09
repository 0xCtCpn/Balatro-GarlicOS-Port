/* SPDX-License-Identifier: GPL-3.0-only
 * Garlic ALSA sink for Balatro port. Same stdin PCM protocol as onion-audio.c:
 * S16LE stereo 44100Hz from parent, but output to ALSA default instead of
 * Onion /dev/dsp server. musl-static + alsa-lib, no LD_PRELOAD needed.
 * Garlic modification 2026, released under GPLv3 to match upstream. */
#include <errno.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <alsa/asoundlib.h>

static volatile sig_atomic_t stopping;
static void stop(int sig) { (void)sig; stopping = 1; }

int main(void) {
    struct sigaction sa = { .sa_handler = stop };
    sigemptyset(&sa.sa_mask);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGPIPE, &sa, NULL);

    snd_pcm_t *pcm = NULL;
    const char *dev = getenv("BALATRO_ALSA_DEVICE");
    if (!dev) dev = "default";
    int rc = snd_pcm_open(&pcm, dev, SND_PCM_STREAM_PLAYBACK, 0);
    if (rc < 0) { fprintf(stderr, "[audio] alsa open %s: %s\n", dev, snd_strerror(rc)); return 1; }
    snd_pcm_hw_params_t *hp;
    snd_pcm_hw_params_alloca(&hp);
    snd_pcm_hw_params_any(pcm, hp);
    snd_pcm_hw_params_set_access(pcm, hp, SND_PCM_ACCESS_RW_INTERLEAVED);
    snd_pcm_hw_params_set_format(pcm, hp, SND_PCM_FORMAT_S16_LE);
    snd_pcm_hw_params_set_rate(pcm, hp, 44100, 0);
    snd_pcm_hw_params_set_channels(pcm, hp, 2);
    snd_pcm_hw_params_set_period_size(pcm, hp, 1024, 0);
    snd_pcm_hw_params_set_buffer_size(pcm, hp, 4096);
    rc = snd_pcm_hw_params(pcm, hp);
    if (rc < 0) { fprintf(stderr, "[audio] alsa hwparams: %s\n", snd_strerror(rc)); return 1; }
    snd_pcm_prepare(pcm);
    fprintf(stderr, "[audio] garlic ALSA: 44100 Hz stereo dev=%s\n", dev);

    static short buf[2048]; /* 1024 frames stereo */
    int result = 1;
    unsigned long long total_frames = 0;
    int logged_first = 0;
    while (!stopping) {
        ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
        if (n == 0) { result = 0; break; }
        if (n < 0) {
            if (errno == EINTR) continue;
            perror("[audio] read mixer");
            break;
        }
        size_t frames = (size_t)n / 4;
        short *p = buf;
        while (frames > 0 && !stopping) {
            snd_pcm_sframes_t w = snd_pcm_writei(pcm, p, frames);
            if (w > 0) {
                p += w * 2; frames -= (size_t)w; total_frames += (unsigned long long)w;
                if (!logged_first) {
                    logged_first = 1;
                    fprintf(stderr, "[audio] first write ok\n");
                }
                continue;
            }
            if (w == -EINTR) continue;
            if (w == -EPIPE || w == -ESTRPIPE) {
                snd_pcm_recover(pcm, (int)w, 0);
                continue;
            }
            if (w == -EAGAIN) {
                struct pollfd pfd;
                int nfds = snd_pcm_poll_descriptors(pcm, &pfd, 1);
                poll(&pfd, nfds > 0 ? 1 : 0, 1000);
                continue;
            }
            fprintf(stderr, "[audio] alsa write: %s\n", snd_strerror((int)w));
            goto done;
        }
    }
done:;
    fprintf(stderr, "[audio] exit frames=%llu stopping=%d\n", total_frames, (int)stopping);
    snd_pcm_drain(pcm);
    snd_pcm_close(pcm);
    return result;
}
