/* EDFBrowser Mac additions, 2026. GPL-3.0-only. See LICENSE. */
#include "include/CDSP.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include "upstream/third_party/fidlib/fidlib.h"
#include "upstream/third_party/kiss_fft/kiss_fftr.h"
#include "upstream/filt/pt_qrs.h"
#include "upstream/filt/plif_eeg_subtract_filter.h"
#include "upstream/filt/ravg_filter.h"
#include "upstream/filt/spike_filter.h"
#include "upstream/filt/remez.h"

int em_filter(double *values, int count, double rate, const char *spec, char *error, int error_size) {
    FidFilter *filter = NULL;
    char *copy = strdup(spec), *cursor = copy;
    if (!copy) return -1;
    char *err = fid_parse(rate, &cursor, &filter);
    if (err) { snprintf(error, error_size, "%s", err); free(err); free(copy); return -1; }
    free(copy);
    if (!filter) return -1;
    double (*run_func)(void *, double) = NULL;
    void *run = fid_run_new(filter, &run_func);
    if (!run || !run_func) { free(filter); return -1; }
    void *buf = fid_run_newbuf(run);
    if (!buf) { fid_run_free(run); free(filter); return -1; }
    for (int i = 0; i < count; i++) values[i] = run_func(buf, values[i]);
    fid_run_freebuf(buf); fid_run_free(run); free(filter);
    return 0;
}

int em_qrs(const double *values, int count, double rate, double scale, double *seconds, int capacity) {
    ptqrsset_t *qrs = create_pt_qrs(rate, 1.0);
    if (!qrs) return -1;
    int n = 0;
    for (int i = 0; i < count; i++) {
        int delay = run_pt_qrs(values[i] * scale, qrs);
        if (delay > 0 && n < capacity) seconds[n++] = (i - delay) / rate;
    }
    free_pt_qrs(qrs); return n;
}

int em_fft(const double *values, int count, double *real, double *imag) {
    if (count < 4 || count % 2) return -1;
    kiss_fftr_cfg cfg = kiss_fftr_alloc(count, 0, NULL, NULL);
    kiss_fft_cpx *out = calloc(count / 2 + 1, sizeof(kiss_fft_cpx));
    kiss_fft_scalar *in = malloc(count * sizeof(kiss_fft_scalar));
    if (!cfg || !out || !in) { free(cfg); free(out); free(in); return -1; }
    for (int i = 0; i < count; i++) in[i] = values[i];
    kiss_fftr(cfg, in, out);
    for (int i = 0; i <= count / 2; i++) { real[i] = out[i].r; imag[i] = out[i].i; }
    free(cfg); free(out); free(in); return 0;
}

int em_powerline(double *values, int count, int rate, int frequency) {
    plifeegfilt_t *f = plif_eeg_create_subtract_filter(rate, frequency);
    if (!f) return -1;
    for (int i = 0; i < count; i++) values[i] = plif_eeg_run_subtract_filter(values[i], f);
    plif_eeg_free_subtract_filter(f); return 0;
}

int em_average(double *values, int count, int size, int high_pass) {
    ravgfiltset_t *f = create_ravg_filter(high_pass ? 0 : 1, size);
    if (!f) return -1;
    for (int i=0; i<count; i++) values[i] = run_ravg_filter(values[i], f);
    free_ravg_filter(f); return 0;
}
int em_spike(double *values, int count, int rate, double velocity, int holdoff) {
    spikefiltset_t *f = create_spike_filter(rate, velocity, holdoff, NULL);
    if (!f) return -1;
    for (int i=0; i<count; i++) values[i] = run_spike_filter(values[i], f);
    free_spike_filter(f); return 0;
}
int em_remez(double rate, double low, double high, double transition, double *coefficients, int capacity) {
    double start[3], stop[3], gain[3], ripple[3]; int bands;
    if (low == 0) {
        bands=2; start[0]=0; stop[0]=high; gain[0]=1; ripple[0]=1;
        start[1]=high+transition; stop[1]=rate/2; gain[1]=0; ripple[1]=-60;
    } else {
        bands=3; start[0]=0; stop[0]=low-transition; gain[0]=0; ripple[0]=-60;
        start[1]=low; stop[1]=high; gain[1]=1; ripple[1]=1;
        start[2]=high+transition; stop[2]=rate/2; gain[2]=0; ripple[2]=-60;
    }
    double *taps=NULL; int abort_flag=0;
    int count=remez(rate,bands,start,stop,gain,ripple,&taps,&abort_flag);
    if (count > capacity) { free(taps); return -100; }
    if (count > 0 && taps) memcpy(coefficients,taps,count*sizeof(double));
    free(taps); return count;
}
