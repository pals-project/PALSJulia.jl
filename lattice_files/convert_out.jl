xi = [1]
yi = [2]
zi = [3]
pxi = [4]
pyi = [5]
pzi = [6]
v = [ xi pxi py pyi zi pzi ]
ap1 = LineElement(kind = Aperture,L = 1,x1_limit = 1,x2_limit = 2,y1_limit = 3,y2_limit = 4,aperture_shape = ApertureShape.Elliptical,aperture_at = ApertureAt.Entrance,aperture_shifts_with_body = false,aperture_active = true,)
marker1 = LineElement(kind = Marker,)
drift1 = LineElement(kind = Drift,L = 100,)
ap2 = LineElement(kind = Aperture,L = 0,)
s1 = LineElement(kind = SBend,L = 10,e1 = 9.1,e2 = -10.2,edge1_int = 1.3,edge2_int = 1.4,g_ref = 1.5,tilt_ref = 2.0,x_offset = 9.1,y_offset = 9.2,z_offset = 9.3,x_rot = -1,y_rot = -2,tilt = -3,)
quad1 = LineElement(kind = Quadrupole,L = 0.01,tilt1 = 1,Kn1 = 32,Ks1 = 10,dE_ref = -0.2,)
sext1 = LineElement(kind = Sextupole,L = 0.02,tilt3 = 1,Bn3L = 32,Bs3L = 10,)
sol1 = LineElement(kind = Solenoid,Ksol = 10,)
multipole1 = LineElement(kind = Multipole,L = 37.6,tilt1 = 1,tilt2 = 2,tilt4 = 10.3,Kn9L = 11,tilt9 = 2,Bn4L = 2,Bs4L = 3,Kn2 = 1,Ks2 = 10,Bn1 = 3,Bs1 = 9,Ks9L = 12,tracking_method = SciBmadStandard(),)
patch4 = LineElement(kind = Patch,L = 0,dx = 1.1,dy = 1.2,dz = 1.3,dx_rot = 1.4,dy_rot = 1.5,dz_rot = 1.6,)
rfcav1 = LineElement(kind = RFCavity,L = 1.3,rate = 100000,rate_meaning = false,voltage = 100,phi0 = 19.477874452256717,traveling_wave = false,zero_phase = Accelerating,tracking_method = SaganCavity(num_cells = 0, L_active = 0.0),)
rfcav2 = LineElement(kind = RFCavity,L = 1.3,rate = 2000,rate_meaning = true,voltage = 100,phi0 = 19.477874452256717,traveling_wave = false,zero_phase = BelowTransition,tracking_method = SaganCavity(num_cells = 0, L_active = 0.0),)
rfcav3 = LineElement(kind = RFCavity,L = 1.3,voltage = 100,phi0 = 19.477874452256717,traveling_wave = true,zero_phase = AboveTransition,rate_meaning = -1,tracking_method = SaganCavity(num_cells = 0, L_active = 0.0),)
beambeam1 = LineElement(kind = BeamBeam,L = 0.2,sigma_x = 1,sigma_y = 2,sigma_z = 3,alpha_x = 4,beta_x = 5,alpha_y = 6,beta_y = 7,charge = 1,energy = 2E10,N_particle = 1E3,)
sext1 = LineElement(kind = Sextupole,L = 0.02,tilt3 = 1,Bn3L = 32,Bs3L = 10t1,)
Beamline([marker1,ap1,drift1,ap2,s1,quad1,sext1,sol1,multipole1,patch1,rfcav1,rfcav2,rfcav3,beambeam1,], species_ref = electron,pc_ref = 3E6,)
