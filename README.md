# beaufort_jet
Idealized ROMS model of the Alaskan Beafort shelf. Based on a fork of Rob Hetland's and Dylan Schlichting's ```shelfstrat``` repo. The model is currently setup as a jet that undergoes baroclinic instability. It is run as an initial value problem and can be run as an unforced initial value problem, or forced with bulk fluxes. If forced with surface cooling, vertical stratification is required to prevent grid scale noise developing seaward of the jet. 

To generate the grid and initial conditions, load a python environment with xarray support, and edit paths in these files
```
python grd/make_grid.py

python ini/make_ini.py
```
Bathymetry is based on GEBCO and fit with a hyperbolic tangent function that is artificially shoaled to enforce a minimum water depth of 5 m. This could be modified to be more like the observations, see ```grd/gebco_roms_bathymetry.ipynb``` for a comparison. 

## Initial conditions

### 1. Jet density gradient (Gaussian in y)
$$
M_2(y) = M_{2,\max} \exp \left[-\left(\frac{y - y_0}{L_{\mathrm{jet}}}\right)^2\right]
$$

Where:  
- $$M_{2,\max}$$ = maximum horizontal density gradient  
- $$L_{\mathrm{jet}}$$ = Gaussian half-width of the jet  
- $$y_0$$ = jet center  

---

### 2. Convert density gradient to salinity gradient
$$
\frac{\partial S}{\partial y} = \frac{M_2(y)}{g \, SCOEF}
$$

Where:  
- $$g$$ = gravitational acceleration  
- $$SCOEF$$ = haline contraction coefficient  

---

### 3. Integrate to get salinity anomaly
$$
S'(y) = \int_{y_\text{ref}}^{y} \frac{M_2(y')}{g S_\rho} \, dy'
$$

Shift to match background salinity $$S(y) = S_0 + S'(y) - \min(S')$$

---

### 4. Add vertical stratification to prevent convective instabilities seaward of jet
$$
S(x,y,z) = S + \frac{\partial S}{\partial z} (z)
$$

Where $$z$$ is depth and $$\frac{\partial S}{\partial z}$$ is the prescribed vertical gradient.

---

### 5. Initial velocities
The alongshore velocity is prescribed using a thermal wind balance based on the salinity stratification: 

$$
\frac{\partial u}{\partial z} \approx - \frac{g}{f \rho_0} \frac{\partial S}{\partial y}
$$

Temperature is excluded from the contribution to density because it is horizontally uniform initially.

### 6. Smooth vertical temperature profile
- Use a **hyperbolic tangent** to smoothly transition from bottom to surface temperature across the pycnocline:

$$
T(z) = T_\text{bottom} + 0.5 (T_\text{surface} - T_\text{bottom}) \left[ 1 - \tanh\left(\frac{H_\text{pyc} - z}{\delta}\right) \right]
$$

Where:  
- $$H_\text{pyc}$$ = depth of pycnocline  
- $$\delta$$ = pycnocline thickness  

This creates a continuous, smooth temperature gradient between bottom and surface.

## Compiling and running 
Clone my ROMS branch, which is based on the myroms develop branch v4.1 (I think). Modified to include discrete variance decay (DVD) analysis of temperature mixing and open boundary condition support for sea ice. DVD added by Brianna Undzis, and sea ice modifications added by Tale Bakken Ulfsby, which you can see in the commit history. 
```
git clone -b dylanschlichting/roms-seaice-dvd git@github.com:dylanschlichting/roms.git
```
I suggest you have two directories for executables, one with/without ice so the executable isn't overwritten when switching. Edit ```build_roms_***.sh``` for the correct paths and application name. The relevant / required analytical functions are stored in ```project/Functionals```. 

Then
```
./perlmutter_env.sh
./build_roms_no_ice.sh -j 4 
# or 
./build_roms_ice.sh -j 4
```
That should place an executable ```romsM``` in your project directory. To run, go to your project directory and 
```
# No ice 
salloc --nodes 1 --qos interactive --time 04:00:00 --constraint cpu --account=m4304

srun -n 128 ./romsM ocean_beaufort_jet_unforced_no_ice_dx_1km_dz_40_layers.in >log_no_ice.out 2>&1
srun -n 128 ./romsM ocean_beaufort_jet_bulk_fluxes_ice_dx_1km_dz_40_layers.in >log_ice.out 2>&1
```
Important note: I think there is a bug in the sea ice parallel code. If running with ice on and you give the model "too" many cores, it throws a seg fault. For 1 km, I can't run with more than 128 cores, or 256 cores for 500. This is NOT a problem if sea ice is turned off. 

## Model properties and notes
Edit as you see fit. Both the ice and ice-free models share the following properties:
- 60 sec DT (1 km), 30 sec DT (500 m)
- nEVP = 60 (1km), nEVP = 30 (500 m)
- U3HC4 tracer advection scheme
- k-epsilon vertical mixing
- No nudging
- No lateral mixing for momentum or tracers
- DVD header flags because it will slow the model down. This can be turned on. 

Ice-free model is UNFORCED, so it runs purely as an initial value problem. Ice model requires ```BULK_FLUXES``` to run and form sea ice from the current initial conditions. If you change the with ice application name, you must grep and replace it in all relevant analyticals or compiling/running will break. The model is highly sensitive to nEVP. Try to keep the nEVP timestep at ~1 sec, as in DT / nEVP ~ 1. 

### Changing vertical mixing schemes
To setup KPP, change the following in the header file:
```
#undef GLS_MIXING
#undef CANUTO_A
#undef N2S2_HORAVG

#define LMD_MIXING       /* Large-McWilliams-Doney K-Profile Parameterization */

/* Additional LMD options */
#define LMD_SHAPIRO      /* Shapiro filter for vertical mixing */
#define LMD_RIMIX        /* Richardson number dependent mixing */
#define LMD_CONVEC       /* Convective adjustment */
#define LMD_SKPP         /* Surface KPP scheme */
#define LMD_BKPP         /* Bottom KPP scheme */
#define LMD_NONLOCAL     /* Nonlocal transport */ 

/* TXLA LMD River plume simulations are unstable without this enabled! */
#if defined LMD_MIXING 
# define RI_HORAVG
# define RI_VERAVG
#endif
```
If KPP is very noisy or checkerboards, try ```#undef LMD_NONLOCAL```. 

To change between GLS schemes, you will need to change some compiler flags and the .in file depending on scheme. See Tab. 1-2 of https://www.sciencedirect.com/science/article/pii/S1463500303000702 for coefficient values. For $$k-\epsilon$$, $$k-kl$$, and $$gen$$, try ```#define CANUTO_A```. $k-\omega$ does not require a stability function and I have not tested what happens if Canuto A is used in conjunction with it. 
```
! Relevant part of the .in file

! Generic length-scale turbulence closure parameters.

       GLS_P == 3.0d0                           ! K-epsilon
       GLS_M == 1.5d0
       GLS_N == -1.0d0
    GLS_Kmin == 7.6d-6
    GLS_Pmin == 1.0d-12

    GLS_CMU0 == 0.5477d0
      GLS_C1 == 1.44d0
      GLS_C2 == 1.92d0
     GLS_C3M == -0.4d0
     GLS_C3P == 1.0d0
    GLS_SIGK == 1.0d0
    GLS_SIGP == 1.30d0
```