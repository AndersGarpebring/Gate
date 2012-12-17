#include "optical_fun.cu"
#include "GateGPUIO.hh"

#include <vector>

void GateOpticalBiolum_GPU(const GateGPUIO_Input * input, 
                           GateGPUIO_Output * output) {

  // Select a GPU
  cudaSetDevice(input->cudaDeviceID);

  // Vars
  int particle_simulated = 0;
  int nb_of_particles = input->nb_events;
  float E = input->E;
  long seed = input->seed;
  int i;
  srand(seed);
  
  // Kernel vars
  dim3 threads, grid;
  int block_size = 512;
  int grid_size = (nb_of_particles + block_size - 1) / block_size;
  threads.x = block_size;
  grid.x = grid_size;

  // Photons Stacks
  StackParticle photons_d;
  stack_device_malloc(photons_d, nb_of_particles);
  StackParticle photons_h;
  stack_host_malloc(photons_h, nb_of_particles);
  
  // Init random
  i=0; while(i < nb_of_particles) {photons_h.seed[i] = rand(); ++i;};
  stack_copy_host2device(photons_h, photons_d);
  kernel_brent_init<<<grid, threads>>>(photons_d);
    
  // Phantoms
  Volume<unsigned short int> phantom_mat_d;
  Volume<float> phantom_act_d;
  Volume<unsigned int> phantom_ind_d;

  phantom_mat_d.most_att_data = 1;
  phantom_mat_d.size_in_mm = make_float3(input->phantom_size_x*input->phantom_spacing_x,
				     input->phantom_size_y*input->phantom_spacing_y,
				     input->phantom_size_z*input->phantom_spacing_z);
  phantom_mat_d.voxel_size = make_float3(input->phantom_spacing_x,
				     input->phantom_spacing_y,
				     input->phantom_spacing_z);
  phantom_mat_d.size_in_vox = make_int3(input->phantom_size_x,
				    input->phantom_size_y,
				    input->phantom_size_z);
  phantom_mat_d.nb_voxel_slice = phantom_mat_d.size_in_vox.x * phantom_mat_d.size_in_vox.y;
  phantom_mat_d.nb_voxel_volume = phantom_mat_d.nb_voxel_slice * phantom_mat_d.size_in_vox.z;
  
  phantom_act_d.most_att_data=1;
  phantom_act_d.size_in_mm = phantom_mat_d.size_in_mm;
  phantom_act_d.voxel_size = phantom_mat_d.voxel_size;
  phantom_act_d.size_in_vox = phantom_mat_d.size_in_vox;
  phantom_act_d.nb_voxel_slice = phantom_mat_d.nb_voxel_slice;
  phantom_act_d.nb_voxel_volume = phantom_mat_d.nb_voxel_volume;
  
  phantom_ind_d.most_att_data=1;
  phantom_ind_d.size_in_mm = phantom_mat_d.size_in_mm;
  phantom_ind_d.voxel_size = phantom_mat_d.voxel_size;
  phantom_ind_d.size_in_vox = phantom_mat_d.size_in_vox;
  phantom_ind_d.nb_voxel_slice = phantom_mat_d.nb_voxel_slice;
  phantom_ind_d.nb_voxel_volume = phantom_mat_d.nb_voxel_volume;
  
  phantom_mat_d.mem_data = phantom_mat_d.nb_voxel_volume * sizeof(unsigned short int);
  volume_device_malloc<unsigned short int>(phantom_mat_d, phantom_mat_d.nb_voxel_volume); 
  cudaMemcpy(phantom_mat_d.data, &(input->phantom_material_data[0]), phantom_mat_d.mem_data, cudaMemcpyHostToDevice);

  phantom_act_d.mem_data = phantom_act_d.nb_voxel_volume * sizeof(float);
  volume_device_malloc<float>(phantom_act_d, phantom_act_d.nb_voxel_volume); 
  cudaMemcpy(phantom_act_d.data, &(input->activity_data[0]), phantom_act_d.mem_data, cudaMemcpyHostToDevice);

  phantom_ind_d.mem_data = phantom_ind_d.nb_voxel_volume * sizeof(unsigned int);
  volume_device_malloc<unsigned int>(phantom_ind_d, phantom_ind_d.nb_voxel_volume); 
  cudaMemcpy(phantom_ind_d.data, &(input->activity_index[0]), phantom_ind_d.mem_data, cudaMemcpyHostToDevice);

  // Count simulated photons
  int* count_d;
  int count_h = 0;
  cudaMalloc((void**) &count_d, sizeof(int));
  cudaMemcpy(count_d, &count_h, sizeof(int), cudaMemcpyHostToDevice);

  // Source
  kernel_optical_voxelized_source<float, unsigned int><<<grid, threads>>>(photons_d, 
                                                            phantom_act_d, phantom_ind_d, E);

  // Validation
  stack_copy_device2host(photons_d, photons_h);
  i=0; while (i<nb_of_particles) {
    printf("%e %.2f %.2f %.2f %f %f %f\n", photons_h.E[i], 
                                           photons_h.px[i], photons_h.py[i], photons_h.pz[i],
                                           photons_h.dx[i], photons_h.dy[i], photons_h.dz[i]);
    ++i;
  }

  /*

  // Simualtion loop
  int step = 0;
  while (count_h < nb_of_particles) {
    ++step;
    DD(step);
    DD(count_h);
    //    DD(count_d);
    //kernel_ct_navigation_regular<unsigned short int><<<grid, threads>>>(photons_d, phantom_d, 
    //                                                                    materials_d, count_d);

    // get back the number of simulated photons
    cudaMemcpy(&count_h, count_d, sizeof(int), cudaMemcpyDeviceToHost);
  }

  // Copy photons from device to host
  stack_copy_device2host(photons_d, photons_h);
 
  // DEBUG (not export particles)
  
  i=0;
  while (i<nb_of_particles) {
    
    // Test if the particle was absorbed -> no output.
    if (photons_h.active[i]) {
        GateGPUIO_Particle particle;
        particle.E =  photons_h.E[i];
        particle.dx = photons_h.dx[i];
        particle.dy = photons_h.dy[i];
        particle.dz = photons_h.dz[i];
        particle.px = photons_h.px[i] - (input->phantom_size_x/2.0)*input->phantom_spacing_x;
        particle.py = photons_h.py[i] - (input->phantom_size_y/2.0)*input->phantom_spacing_y;
        particle.pz = photons_h.pz[i] - (input->phantom_size_z/2.0)*input->phantom_spacing_z;
        particle.t =  photons_h.t[i];
        particle.type = photons_h.type[i];
        particle.eventID = photons_h.eventID[i];
        particle.trackID = photons_h.trackID[i];
        
        output->particles.push_back(particle);
    
        //printf("g %e %e %e %e %e %e %e\n", photons_h.E[i], particle.px, particle.py,
        //                  particle.pz, photons_h.dx[i], photons_h.dy[i], photons_h.dz[i]);
    }
    //else {
      // DD("Particle is still in volume. Ignored.");
    //}
    ++i;
  }
  */

  stack_device_free(photons_d);
  stack_host_free(photons_h);
  volume_device_free(phantom_mat_d);
  volume_device_free(phantom_act_d);
  volume_device_free(phantom_ind_d);


  cudaDeviceSynchronize();

  cudaThreadExit();
}




