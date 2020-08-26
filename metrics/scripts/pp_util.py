# Copyright (c) 2020 Performance Portability authors
# SPDX-License-Identifier: MIT

from csv import DictReader, reader
import attr

def harmean(vals):
    try:
        s = sum((1.0/x for x in vals))
    except ZeroDivisionError:
        return 0.0
    return len(vals)/s

@attr.s
class platform(object):
    name = attr.ib()
    arch_bw = attr.ib()
    types = attr.ib(default=attr.Factory(list))
    best_bw = attr.ib(default=None)
    def arch_eff(self, perf, throughput):
        if throughput:
            return perf/self.arch_bw
        else:
            return self.arch_bw/perf
    def app_eff(self, perf, throughput):
        if throughput:
            return perf/self.best_bw
        else:
            return self.best_bw/perf

global platforms

platforms = dict()

def add_platform(name, arch_bw, types):
    platforms[name] = platform(name, float(arch_bw), types)

@attr.s
class perf_entry(object):
    platform = attr.ib()
    perf = attr.ib()

@attr.s
class app(object):
    name = attr.ib()
    perfs = attr.ib(default=attr.Factory(dict))
    @classmethod
    def entries(cls, name, perf_pairs):
        perfs = dict()
        for k, v in perf_pairs:
            perfs[k] = perf_entry(k,float(v))
        return cls(name, perfs)
    def bad_pp_arch(self):
        return harmean([platforms[v.platform].arch_eff(v.perf) for v in self.perfs.values()])
    def bad_pp_app(self):
        return harmean([platforms[v.platform].app_eff(v.perf) for v in self.perfs.values()])
    def arch_pp(self, plats, throughput):
        try:
            vals = [platforms[k].arch_eff(self.perfs[k].perf, throughput) for k in plats]
            return harmean(vals)
        except KeyError:
            return 0.0
    def app_pp(self, plats, throughput):
        try:
            vals = [platforms[k].app_eff(self.perfs[k].perf, throughput) for k in plats]
            return harmean(vals)
        except KeyError:
            return 0.0

global apps

apps = dict()

def add_app(name, pairs):
    apps[name] = app.entries(name, pairs)

def best_plat_perf(plat_name, apps, throughput):
    best = None
    for a in apps:
       for p, v in a.perfs.items():
           if p == plat_name:
               if throughput:
                   if best == None or best < v.perf:
                       best = v.perf
               else:
                   if best == None or best > v.perf:
                       best = v.perf
    return best

def load_app_perfs(appfile, appname=None, throughput=False):
    global apps
    apps=dict()
    global platforms
    platforms=dict()
    with open("../data/spec.csv", "r") as fp:
        plats = DictReader(fp, skipinitialspace=True)
        plat_dict = {}
        for row in plats:
            plat_dict[row["Architecture"]] = row
            add_platform(row["Architecture"], float(row['Mem BW']), row['Category'])
    with open(appfile, "r") as fp:
        perfs = reader(fp, skipinitialspace=True)
        header = [x.strip() for x in next(perfs)]
        for row in perfs:
            plat = row[0]
            for i, item in enumerate(row[1:]):
                appname = header[i+1]
                if appname not in apps:
                    apps[appname] = app(appname)
                if item.strip() == 'X':
                    if throughput:
                        item = 0.0
                    else:
                        item = "inf"
                apps[appname].perfs[plat] = perf_entry(plat, float(item))
    for p in list(platforms.values()):
        p.best_bw = best_plat_perf(p.name, apps.values(), throughput)
        if p.best_bw == 0.0:
            del platforms[p.name]

def get_effs(appfile, appname=None, throughput=False):
    global apps
    global platforms
    load_app_perfs(appfile, appname, throughput)
    res = {}
    for name,theapp in apps.items():
        res[name] = app_effs(theapp, list(platforms.keys()), throughput)
    return res

def read_effs(appfile):
    global apps
    apps = {}
    with open(appfile, "r") as fp:
        perfs = reader(fp, skipinitialspace=True)
        header = [x.strip() for x in next(perfs)]
        for row in perfs:
            plat = row[0]
            for i, item in enumerate(row[1:]):
                appname = header[i+1]
                if appname not in apps:
                    apps[appname] = []
                apps[appname].append(float(item)/100.0)
    s = sorted(list(apps.items()), key=lambda x: harmean(x[1]))
    return s

def app_effs(theapp, plats, throughput):
    perfs = []
    for p in plats:
        if p in theapp.perfs:
            perfs.append(theapp.perfs[p])
    valid_perfs = []
    for p in perfs:
        if p.platform in plats:
            if p.perf > 0 and p.perf != float("inf"):
                valid_perfs.append((p, platforms[p.platform].app_eff(p.perf, throughput)))
            else:
                valid_perfs.append((p, 0.0))
    effs = list(x[1] for x in valid_perfs)
    return effs


import numpy

def gaussian(x):
    return 1.0/numpy.sqrt(2.0*numpy.pi)*numpy.exp(-0.5*x**2.0)

from scipy.special import erf
from scipy.integrate import simps

def gaussian_cdf(x):
    return 0.5*(1.0+erf(x*2**-0.5))

def gaussian_scaling(a, b):
    return -2.0/(erf(a*2**-0.5)+erf(-b*2**-0.5))

class gaussian_family:
    def __init__(self):
        self.kernel_func = gaussian
        self.scaling_func = gaussian_scaling
        self.cdf_func = gaussian_cdf

def bw_estimate(samples):
    sigma = numpy.std(samples)
    cand = ((4*sigma**5.0)/(3.0*len(samples)))**(1.0/5.0)
    if cand < 1e-7:
        return 1.0
    return cand

class akde:
    def __init__(self, x, samples, bw_fac):
        self.clip = True
        self.kernel_family = gaussian_family()
        self.bw_fac = bw_fac
        self.x = x
        self.samples = samples
        self.last_pdf = None
        self.bw0 = bw_estimate(samples)

    def bw_estimate(self, lx):
        if self.last_pdf is None:
            return self.bw0

        return self.bw_fac*(self.density_estimate(lx)**-0.5)

    def density_estimate(self, lx):
        assert self.last_pdf is not None

        loc = numpy.searchsorted(self.x, lx)
        if loc >= len(self.last_pdf):
            return self.last_pdf[-1]
        else:
            return self.last_pdf[loc]

    def pdf(self):
        scaling_func = self.kernel_family.scaling_func
        kernel_func = self.kernel_family.kernel_func
        pdf = numpy.zeros(len(self.x))
        for s in self.samples:
            loc_h = self.bw_estimate(s)
            if self.clip:
                assert s >= self.x[0] and s <= self.x[-1]
                scaling = scaling_func((self.x[0]-s)/loc_h, (self.x[-1]-s)/loc_h)
            else:
                scaling = 1.0
            pdf += 1.0/loc_h * scaling * kernel_func((self.x-s)/loc_h)
        pdf = pdf/len(self.samples)
        self.last_pdf = pdf
        area = simps(pdf, self.x)
        if self.clip:
            assert numpy.fabs(area-1.0) < 1e-3
        return pdf, area

    def pdf_series(self, num):
        self.last_pdf = None
        res = []
        for i in range(num):
            pdf, area = self.pdf()
            res.append(pdf)
        return res

    def pdf_refine(self, num):
        self.last_pdf = None
        for i in range(num):
            pdf, area = self.pdf()
        return pdf

    def cdf(self):
        scaling_func = self.kernel_family.scaling_func
        cdf_func = self.kernel_family.cdf_func
        cdf = numpy.zeros(len(self.x))
        for s in self.samples:
            loc_h = self.bw_estimate(s)
            if self.clip:
                assert s >= self.x[0] and s <= self.x[-1]
                scaling = scaling_func((self.x[0]-s)/loc_h, (self.x[-1]-s)/loc_h)
            else:
                scaling = 1.0
            cdf +=  scaling * (cdf_func((self.x-s)/loc_h)-cdf_func((self.x[0]-s)/loc_h))
        return cdf/len(self.samples)

def pp_cdf(theapp, plats, throughput):
    perfs = []
    for p in plats:
        if p in theapp.perfs:
            perfs.append(theapp.perfs[p])
    valid_perfs = []
    for p in perfs:
        if p.platform in plats:
            if p.perf > 0 and p.perf != float("inf"):
                valid_perfs.append((p, platforms[p.platform].app_eff(p.perf, throughput)))
    sorted_perfs = sorted(valid_perfs, key=lambda x: x[1])
    effs = list(zip(reversed(range(1,len(sorted_perfs)+1)), (x[1] for x in sorted_perfs)))
    perfs = [x[0].platform for x in sorted_perfs]
    pps = []
    for i in range(len(perfs)):
        pps.append((len(perfs)-i, harmean([x[1] for x in sorted_perfs[i:]])))
    return pps, effs

def pp_cdf_raw_effs(theapp):
    valid_effs = [ x for x in theapp  if x > 0 and x != float("inf")]
    sorted_effs = sorted(valid_effs)
    effs = list(zip(reversed(range(len(sorted_effs))), sorted_effs))
    pps = []
    for i in range(len(sorted_effs)):
        pps.append((len(sorted_effs)-i, harmean(sorted_effs[i:])))
    return pps, effs
