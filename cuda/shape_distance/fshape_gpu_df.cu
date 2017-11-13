/* Based on the work of J. Glaunes */
/* Authors : this file is part of the fshapesTk by B. Charlier, N. Charon, A. Trouve (2012-2014) */

#include <stdio.h>
#include <assert.h>
#include <cuda.h>
#include <mex.h>
#include "kernels.cx"

#define UseCudaOnDoubles USE_DOUBLE_PRECISION

///////////////////////////////////////
///// CONV ////////////////////////////
///////////////////////////////////////


// thread kernel: computation of gammai = sum_j k(xi,yj)betaj for index i given by thread id.
template < typename TYPE, int DIMPOINT, int DIMSIG, int DIMVECT >
__global__ void VarFunDfGaussGpuConvOnDevice(TYPE ooSigmax2, TYPE ooSigmaf2, TYPE ooSigmaXi2, 
				     TYPE *x, TYPE *y, 
				     TYPE *f, TYPE *g, 
				     TYPE *alpha, TYPE *beta,
				     TYPE *gamma,
				     int nx, int ny)
{
    int i = blockIdx.x * blockDim.x + threadIdx.x;

    // the following line does not work with nvcc 3.0 (it is a bug; it works with anterior and posterior versions)
    // extern __shared__ TYPE SharedData[];  // shared data will contain x and alpha data for the block
    // here is the bug fix (see http://forums.nvidia.com/index.php?showtopic=166905)
    extern __shared__ char SharedData_char[];
    TYPE* const SharedData = reinterpret_cast<TYPE*>(SharedData_char);
    // end of bug fix

    TYPE xi[DIMPOINT], fi[DIMSIG], alphai[DIMPOINT], gammai[DIMSIG];
    if(i<nx)  // we will compute gammai only if i is in the range
    {
        // load xi from device global memory
        for(int k=0; k<DIMPOINT; k++)
            xi[k] = x[i*DIMPOINT+k];
        for(int k=0; k<DIMSIG; k++)
            fi[k] = f[i*DIMSIG+k];
        for(int k=0; k<DIMVECT; k++)
            alphai[k] = alpha[i*DIMVECT+k];
        for(int k=0; k<DIMSIG; k++)
            gammai[k] = 0.0f;
    }

    for(int jstart = 0, tile = 0; jstart < ny; jstart += blockDim.x, tile++)
    {
        int j = tile * blockDim.x + threadIdx.x;
        if(j<ny) // we load yj and betaj from device global memory only if j<ny
        {
            int inc = DIMPOINT + DIMSIG + DIMVECT;
            for(int k=0; k<DIMPOINT; k++)
                SharedData[threadIdx.x*inc+k] = y[j*DIMPOINT+k];
            for(int k=0; k<DIMSIG; k++)
                SharedData[threadIdx.x*inc+DIMPOINT+k] = g[j*DIMSIG+k];
            for(int k=0; k<DIMVECT; k++)
                SharedData[threadIdx.x*inc+DIMPOINT+DIMSIG+k] = beta[j*DIMVECT+k];
        }
        __syncthreads();
        
        if(i<nx) // we compute gammai only if needed
        {
            TYPE *yj, *gj, *betaj;
            yj = SharedData;
	    gj = SharedData + DIMPOINT;
            betaj = SharedData + DIMPOINT + DIMSIG;
            int inc = DIMPOINT + DIMSIG + DIMVECT;
            for(int jrel = 0; jrel < blockDim.x && jrel<ny-jstart; jrel++, yj+=inc, gj +=inc, betaj+=inc)
            {
		    // distance between points and signals
		    TYPE dist2_geom = sq_dist<TYPE,DIMPOINT>(xi,yj);
		    TYPE dist2_sig = sq_dist<TYPE,DIMSIG>(fi,gj);

		    // Angles between normals
		    TYPE norm2Xix = 0.0f, norm2Xiy = 0.0f, prsxy = 0.0f;
		    for(int k=0; k<DIMVECT; k++) {
			    norm2Xix += alphai[k]*alphai[k]; 
			    norm2Xiy += betaj[k]*betaj[k];
			    prsxy +=  alphai[k]*betaj[k];
		    }
		    TYPE angle_normals = prsxy  * rsqrt(norm2Xix*norm2Xiy);

		TYPE s = sqrt(norm2Xix * norm2Xiy) * Kernel_geom1(dist2_geom,ooSigmax2) * dKernel_sig1(dist2_sig,ooSigmaf2) * Kernel_var1(angle_normals,ooSigmaXi2);
		    for (int k = 0; k < DIMSIG; k++)
		    {
                	gammai[k] += 2 * (fi[k] - gj[k]) *s ;
		    }
            }
        }
        __syncthreads();
    }

    // Save the result in global memory.
    if(i<nx){
    		for (int k = 0; k < DIMSIG; k++){
            	gamma[i*DIMSIG+k] = gammai[k];
		}
	}
    
}

///////////////////////////////////////////////////

extern "C" int VarFunDfGaussGpuEvalConv_float(float ooSigmax2,float ooSigmaf2, float ooSigmaXi2,
                                   float* x_h, float* y_h,
                                   float* f_h, float* g_h,
				   float* alpha_h, float* beta_h, 
				   float* gamma_h,
                                   int dimPoint, int dimSig, int dimVect, int nx, int ny)
{

    // Data on the device.
    float* x_d;
    float* y_d;
    float* f_d;
    float* g_d;
    float* alpha_d;
    float* beta_d;
    float* gamma_d;

    // Allocate arrays on device.
    cudaMalloc((void**)&x_d, sizeof(float)*(nx*dimPoint));
    cudaMalloc((void**)&y_d, sizeof(float)*(ny*dimPoint));
    cudaMalloc((void**)&f_d, sizeof(float)*(nx*dimSig));
    cudaMalloc((void**)&g_d, sizeof(float)*(ny*dimSig));
    cudaMalloc((void**)&alpha_d, sizeof(float)*(nx*dimVect));
    cudaMalloc((void**)&beta_d, sizeof(float)*(ny*dimVect));
    cudaMalloc((void**)&gamma_d, sizeof(float)*nx*dimSig);

    // Send data from host to device.
    cudaMemcpy(x_d, x_h, sizeof(float)*(nx*dimPoint), cudaMemcpyHostToDevice);
    cudaMemcpy(y_d, y_h, sizeof(float)*(ny*dimPoint), cudaMemcpyHostToDevice);
    cudaMemcpy(f_d, f_h, sizeof(float)*(nx*dimSig), cudaMemcpyHostToDevice);
    cudaMemcpy(g_d, g_h, sizeof(float)*(ny*dimSig), cudaMemcpyHostToDevice);
    cudaMemcpy(alpha_d, alpha_h, sizeof(float)*(nx*dimVect), cudaMemcpyHostToDevice);
    cudaMemcpy(beta_d, beta_h, sizeof(float)*(ny*dimVect), cudaMemcpyHostToDevice);

    // Compute on device.
    dim3 blockSize;
    blockSize.x = CUDA_BLOCK_SIZE; // number of threads in each block
    dim3 gridSize;
    gridSize.x =  nx / blockSize.x + (nx%blockSize.x==0 ? 0 : 1);

    if(dimPoint==1 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<float,1,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(float)>>>
        (ooSigmax2,ooSigmaf2,ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==3 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<float,3,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(float)>>>
        (ooSigmax2,ooSigmaf2,ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==2 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<float,2,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(float)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==2 && dimSig==1 && dimVect==2)
        VarFunDfGaussGpuConvOnDevice<float,2,1,2><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(float)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==3 && dimSig==1 && dimVect==3)
        VarFunDfGaussGpuConvOnDevice<float,3,1,3><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(float)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else
    {
        printf("error: dimensions of Gauss kernel not implemented in cuda");
		cudaFree(x_d);
		cudaFree(y_d);
		cudaFree(f_d);
		cudaFree(g_d);
		cudaFree(alpha_d);
		cudaFree(beta_d);
		cudaFree(gamma_d);
        return(-1);
    }

    // block until the device has completed
    cudaThreadSynchronize();

    // Send data from device to host.
    cudaMemcpy(gamma_h, gamma_d, sizeof(float)*nx*dimSig,cudaMemcpyDeviceToHost);

    // Free memory.
    cudaFree(x_d);
    cudaFree(y_d);
    cudaFree(f_d);
    cudaFree(g_d);
    cudaFree(beta_d);
    cudaFree(gamma_d);
    cudaFree(alpha_d);
    return 0;
}

///////////////////////////////////////////////////

#if UseCudaOnDoubles  
extern "C" int VarFunDfGaussGpuEvalConv_double(double ooSigmax2,double ooSigmaf2, double ooSigmaXi2,
                                   double* x_h, double* y_h,
                                   double* f_h, double* g_h,
				   double* alpha_h, double* beta_h, 
				   double* gamma_h,
                                   int dimPoint, int dimSig, int dimVect, int nx, int ny)
{

    // Data on the device.
    double* x_d;
    double* y_d;
    double* f_d;
    double* g_d;
    double* alpha_d;
    double* beta_d;
    double* gamma_d;

    // Allocate arrays on device.
    cudaMalloc((void**)&x_d, sizeof(double)*(nx*dimPoint));
    cudaMalloc((void**)&y_d, sizeof(double)*(ny*dimPoint));
    cudaMalloc((void**)&f_d, sizeof(double)*(nx*dimSig));
    cudaMalloc((void**)&g_d, sizeof(double)*(ny*dimSig));
    cudaMalloc((void**)&alpha_d, sizeof(double)*(nx*dimVect));
    cudaMalloc((void**)&beta_d, sizeof(double)*(ny*dimVect));
    cudaMalloc((void**)&gamma_d, sizeof(double)*nx*dimSig);

    // Send data from host to device.
    cudaMemcpy(x_d, x_h, sizeof(double)*(nx*dimPoint), cudaMemcpyHostToDevice);
    cudaMemcpy(y_d, y_h, sizeof(double)*(ny*dimPoint), cudaMemcpyHostToDevice);
    cudaMemcpy(f_d, f_h, sizeof(double)*(nx*dimSig), cudaMemcpyHostToDevice);
    cudaMemcpy(g_d, g_h, sizeof(double)*(ny*dimSig), cudaMemcpyHostToDevice);
    cudaMemcpy(alpha_d, alpha_h, sizeof(double)*(nx*dimVect), cudaMemcpyHostToDevice);
    cudaMemcpy(beta_d, beta_h, sizeof(double)*(ny*dimVect), cudaMemcpyHostToDevice);

    // Compute on device.
    dim3 blockSize;
    blockSize.x = CUDA_BLOCK_SIZE; // number of threads in each block
    dim3 gridSize;
    gridSize.x =  nx / blockSize.x + (nx%blockSize.x==0 ? 0 : 1);

    if(dimPoint==1 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<double,1,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(double)>>>
        (ooSigmax2,ooSigmaf2,ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==3 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<double,3,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(double)>>>
        (ooSigmax2,ooSigmaf2,ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==2 && dimSig==1 && dimVect==1)
        VarFunDfGaussGpuConvOnDevice<double,2,1,1><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(double)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==2 && dimSig==1 && dimVect==2)
        VarFunDfGaussGpuConvOnDevice<double,2,1,2><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(double)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else if(dimPoint==3 && dimSig==1 && dimVect==3)
        VarFunDfGaussGpuConvOnDevice<double,3,1,3><<<gridSize,blockSize,blockSize.x*(dimVect+dimSig+dimPoint)*sizeof(double)>>>
        (ooSigmax2,ooSigmaf2, ooSigmaXi2, x_d, y_d, f_d, g_d, alpha_d, beta_d, gamma_d, nx, ny);
    else
    {
        printf("error: dimensions of Gauss kernel not implemented in cuda");
		cudaFree(x_d);
		cudaFree(y_d);
		cudaFree(f_d);
		cudaFree(g_d);
		cudaFree(alpha_d);
		cudaFree(beta_d);
		cudaFree(gamma_d);
        return(-1);
    }

    // block until the device has completed
    cudaThreadSynchronize();

    // Send data from device to host.
    cudaMemcpy(gamma_h, gamma_d, sizeof(double)*nx*dimSig,cudaMemcpyDeviceToHost);

    // Free memory.
    cudaFree(x_d);
    cudaFree(y_d);
    cudaFree(f_d);
    cudaFree(g_d);
    cudaFree(beta_d);
    cudaFree(gamma_d);
    cudaFree(alpha_d);
    return 0;
}
#endif

void ExitFcn(void)
{
  cudaDeviceReset();
}


//////////////////////////////////////////////////////////////////
///////////////// MEX ENTRY POINT ////////////////////////////////
//////////////////////////////////////////////////////////////////

 
 /* the gateway function */
 void mexFunction( int nlhs, mxArray *plhs[],
                   int nrhs, const mxArray *prhs[])
 //plhs: double *gamma
 //prhs: double *x, double *y, double *beta, double sigma
 
 { 

   // register an exit function to prevent crash at matlab exit or recompiling
   mexAtExit(ExitFcn);

   /*  check for proper number of arguments */
   if(nrhs != 9) 
     mexErrMsgTxt("9 inputs required.");
   if(nlhs < 1 | nlhs > 1) 
     mexErrMsgTxt("One output required.");
 
   //////////////////////////////////////////////////////////////
   // Input arguments
   //////////////////////////////////////////////////////////////
   
   int argu = -1;
 
   //----- the first input argument: x--------------//
   argu++;
   /*  create a pointer to the input vectors srcs */
   double *x = mxGetPr(prhs[argu]);
   /*  input sources */
   int dimpoint = mxGetM(prhs[argu]); //mrows
   int nx = mxGetN(prhs[argu]); //ncols
 
   //----- the second input argument: y--------------//
   argu++;
   /*  create a pointer to the input vectors trgs */
   double *y = mxGetPr(prhs[argu]);
   /*  get the dimensions of the input targets */
   int ny = mxGetN(prhs[argu]); //ncols
   /* check to make sure the first dimension is dimpoint */
   if( mxGetM(prhs[argu])!=dimpoint ) {
     mexErrMsgTxt("Input y must have same number of rows as x.");
   }

   //----- the third input argument: f--------------//
   argu++;
   /*  create a pointer to the input vectors srcs */
   double *f = mxGetPr(prhs[argu]);
   /*  get dimension of the signal */
   int dimsig = mxGetM(prhs[argu]); //mrows
   /* check to make sure the second dimension is nx and fist dim is 1*/
   if( mxGetM(prhs[argu])*mxGetN(prhs[argu])!=nx ) {
     mexErrMsgTxt("Input f must be a vector with the same number of columns as x.");
   }
 
   //----- the fourth input argument: g--------------//
   argu++;
   /*  create a pointer to the input vectors trgs */
   double *g = mxGetPr(prhs[argu]);
   /* check to make sure the second dimension is ny and first dim is 1 */
   if( mxGetM(prhs[argu])*mxGetN(prhs[argu])!=ny ) {
     mexErrMsgTxt("Input g must be a vector with the same number of columns as y.");
   }
    
  //------ the fifth input argument: alpha---------------//
   argu++;
   /*  create a pointer to the input vectors wts */
   double *alpha = mxGetPr(prhs[argu]);
   /*  get the dimensions of the input weights */
   int dimvect = mxGetM(prhs[argu]);
   /* check to make sure the second dimension is nx */
   if( mxGetN(prhs[argu])!=nx ) {
     mexErrMsgTxt("Input alpha must have same number of columns as x.");
   }

  //------ the sixth input argument: beta---------------//
   argu++;
   /*  create a pointer to the input vectors wts */
   double *beta = mxGetPr(prhs[argu]);
   /*  get the dimensions of the input weights */
   if (dimvect != mxGetM(prhs[argu])){
	   mexErrMsgTxt("Input beta must have the same number of row as alpha");}
   /* check to make sure the second dimension is ny */
   if( mxGetN(prhs[argu])!=ny ) {
     mexErrMsgTxt("Input beta must have same number of columns as y.");
   }
 
   //----- the seventh input argument: sigmax-------------//
   argu++;
   /* check to make sure the input argument is a scalar */
   if( !mxIsDouble(prhs[argu]) || mxIsComplex(prhs[argu]) ||
       mxGetN(prhs[argu])*mxGetM(prhs[argu])!=1 ) {
     mexErrMsgTxt("Input sigmax must be a scalar.");
   }
   /*  get the input sigma */
   double sigmax = mxGetScalar(prhs[argu]);
   if (sigmax <= 0.0)
 	  mexErrMsgTxt("Input sigma must be a positive number.");
   double oosigmax2 = 1.0f/(sigmax*sigmax);
   
   //----- the eighth input argument: sigmaf-------------//
   argu++;
   /* check to make sure the input argument is a scalar */
    if( !mxIsDouble(prhs[argu]) || mxIsComplex(prhs[argu]) ||
       mxGetN(prhs[argu])*mxGetM(prhs[argu])!=1 ) {
     mexErrMsgTxt("Input sigmaf must be a scalar.");
   }
   /*  get the input sigma */
   double sigmaf = mxGetScalar(prhs[argu]);
   if (sigmaf <= 0.0){
	  mexErrMsgTxt("Input sigmaf must be a positive number.");
   }
   double oosigmaf2=1.0f/(sigmaf*sigmaf);

   //----- the ninth input argument: sigmaXi-------------//
   argu++;
   /* check to make sure the input argument is a scalar */
    if( !mxIsDouble(prhs[argu]) || mxIsComplex(prhs[argu]) ||
       mxGetN(prhs[argu])*mxGetM(prhs[argu])!=1 ) {
     mexErrMsgTxt("Input sigmaxi must be a scalar.");
   }
   /*  get the input sigma */
   double sigmaXi = mxGetScalar(prhs[argu]);
   if (sigmaXi <= 0.0){
	  mexErrMsgTxt("Input sigmaxi must be a positive number.");
   }
   double oosigmaXi2=1.0f/(sigmaXi*sigmaXi);


   //////////////////////////////////////////////////////////////
   // Output arguments
   //////////////////////////////////////////////////////////////
   /*  set the output pointer to the output result(vector) */
   plhs[0] = mxCreateDoubleMatrix(dimsig,nx,mxREAL);
   
   /*  create a C pointer to a copy of the output result(vector)*/
   double *gamma = mxGetPr(plhs[0]);
   
#if UseCudaOnDoubles   
   VarFunDfGaussGpuEvalConv_double(oosigmax2,oosigmaf2,oosigmaXi2,x,y,f,g,alpha,beta,gamma,dimpoint,dimsig,dimvect,nx,ny);
#else
   // convert to float
   
   float *x_f = new float[nx*dimpoint];
   for(int i=0; i<nx*dimpoint; i++)
     x_f[i] = x[i];

   float *y_f = new float[ny*dimpoint];
   for(int i=0; i<ny*dimpoint; i++)
     y_f[i] = y[i];

   float *f_f = new float[nx*dimsig];
   for(int i=0; i<nx*dimsig; i++)
     f_f[i] = f[i];
   
   float *g_f = new float[ny*dimsig];
   for(int i=0; i<ny*dimsig; i++)
     g_f[i] = g[i];

   float *alpha_f = new float[nx*dimvect];
   for(int i=0; i<nx*dimvect; i++)
     alpha_f[i] = alpha[i];

   float *beta_f = new float[ny*dimvect];
   for(int i=0; i<ny*dimvect; i++)
     beta_f[i] = beta[i];
 
   
   // function calls;
   float *gamma_f = new float[nx*dimsig];
   VarFunDfGaussGpuEvalConv_float(oosigmax2,oosigmaf2,oosigmaXi2,x_f,y_f,f_f,g_f,alpha_f,beta_f,gamma_f,dimpoint,dimsig,dimvect,nx,ny);
 
   for(int i=0; i<nx*dimsig; i++)
       gamma[i] = gamma_f[i];

   delete [] x_f;
   delete [] y_f;
   delete [] f_f;
   delete [] g_f;
   delete [] alpha_f;
   delete [] beta_f;
   delete [] gamma_f;
#endif
   
   return;
   
 }


