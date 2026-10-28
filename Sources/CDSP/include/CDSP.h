#ifndef EDFMAC_DSP_H
#define EDFMAC_DSP_H
#include <stddef.h>
#include "../upstream/edflib.h"
int em_filter(double *values, int count, double rate, const char *spec, char *error, int error_size);
int em_qrs(const double *values, int count, double rate, double microvolt_scale, double *seconds, int capacity);
int em_fft(const double *values, int count, double *real, double *imag);
int em_powerline(double *values, int count, int rate, int frequency);
int em_average(double *values, int count, int size, int high_pass);
int em_spike(double *values, int count, int rate, double velocity, int holdoff);
int em_remez(double rate, double low, double high, double transition, double *coefficients, int capacity);
#endif
