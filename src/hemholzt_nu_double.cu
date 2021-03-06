#include "channel.h"

static __global__ void cast_kernel(float2* u,double2* v,domain_t domain)
{

  int i = blockIdx.x * blockDim.x + threadIdx.x;
  int k = blockIdx.y * blockDim.y + threadIdx.y;

  int j=k%NY;
  k=(k-j)/NY;

  int h=i*NY*NZ+k*NY+j;

  if(i<NXSIZE/NSTEPS & k<NZ & j<NY){

    float2 ud;
    double2 vd;

    vd=v[h];

    /*
      ud.x=__double2float_rn(vd.x);
      ud.y=__double2float_rn(vd.y);
    */
	
    ud.x=(float)(vd.x);
    ud.y=(float)(vd.y);


    u[h]=ud;

  }

}

static __global__ void rhs_A_kernel(double2* v,float2* u,domain_t domain)
{  

  //Define shared memory


  __shared__ double2 sf[NY+2];

  int k   = blockIdx.x;
  int i   = blockIdx.y;

  int j   = threadIdx.x;


  int h=i*NZ*NY+k*NY+j;

  double2 u_temp;
		
  double2 ap_1;
  double2 ac_1;
  double2 am_1;

  double a=Fmesh((j+1)*DELTA_Y-1.0)-Fmesh(j*DELTA_Y-1.0);
  double b=Fmesh((j-1)*DELTA_Y-1.0)-Fmesh(j*DELTA_Y-1.0);	

  double alpha=-(-b*b*b-a*b*b+a*a*b)/(a*a*a-4.0*a*a*b+4.0*a*b*b-b*b*b);
  double betha=-( a*a*a+b*a*a-b*b*a)/(a*a*a-4.0*a*a*b+4.0*a*b*b-b*b*b);


  if(i<NXSIZE/NSTEPS & k<NZ & j<NY){

    //Read from global so shared

    sf[j+1].x=(double)u[h].x;
    sf[j+1].y=(double)u[h].y;

    __syncthreads();

    ap_1=sf[j+2];	
    ac_1=sf[j+1];
    am_1=sf[j];
		
		
    u_temp.x=(alpha*ap_1.x+ac_1.x+betha*am_1.x);
    u_temp.y=(alpha*ap_1.y+ac_1.y+betha*am_1.y);

    if(j==0){
      u_temp.x=0.0;
      u_temp.y=0.0;		
    }		
	
    if(j==NY-1){
      u_temp.x=0.0;
      u_temp.y=0.0;		
    }	

    v[h]=u_temp;
 	
  }

}

static __global__ void setDiagkernel(double2* ldiag,double2* cdiag,double2* udiag,int nstep,domain_t domain){  

	
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  int k = blockIdx.y * blockDim.y + threadIdx.y;

  int j=k%NY;
  k=(k-j)/NY;

  // [i,k,j][NX,NZ,NY]	

  int h=i*NY*NZ+k*NY+j;

  if (i<NXSIZE/NSTEPS && j<NY && k<NZ)
    {

      double k1;
      double k3;
	
      double kk;
	
      int stride=nstep*NXSIZE/NSTEPS;	

      // X indices		
      k1=(i+IGLOBAL+stride)<NX/2 ? (double)(i+IGLOBAL+stride) : (double)(i+IGLOBAL+stride)-(double)NX ;
		
      // Z indices
      k3=(double)k;
	
      //Fraction
      k1=(PI2/LX)*k1;
      k3=(PI2/LZ)*k3;	

      kk=k1*k1+k3*k3;


      //COEFICIENTS OF THE NON_UNIFORM GRID

      double a=Fmesh((j+1)*DELTA_Y-1.0)-Fmesh(j*DELTA_Y-1.0);
      double b=Fmesh((j-1)*DELTA_Y-1.0)-Fmesh(j*DELTA_Y-1.0);	
	

      double A=-12.0*b/(a*a*a-b*b*b-4.0*a*a*b+4.0*b*b*a);
      double B= 12.0*a/(a*a*a-b*b*b-4.0*a*a*b+4.0*b*b*a);
      double C=-A-B;
		
      double alpha=-(-b*b*b-a*b*b+a*a*b)/(a*a*a-4.0*a*a*b+4.0*a*b*b-b*b*b);
      double betha=-( a*a*a+b*a*a-b*b*a)/(a*a*a-4.0*a*a*b+4.0*a*b*b-b*b*b);

		
		

      //veamos
	
      double2 ldiag_h;
      double2 cdiag_h;
      double2 udiag_h;
	
      udiag_h.x=A-kk*alpha;
      udiag_h.y=0.0;

      cdiag_h.x=C-kk;
      cdiag_h.y=0.0;

      ldiag_h.x=B-kk*betha;
      ldiag_h.y=0.0;

      //To be improved 
		
      if(j==0){
	ldiag_h.x=0.0;
	cdiag_h.x=1.0;
	udiag_h.x=0.0;
      }
	
      if(j==1){
	ldiag_h.x=0.0;
      }

      if(j==NY-1){
	ldiag_h.x=0.0;
	cdiag_h.x=1.0;
	udiag_h.x=0.0;
      }	
	
      if(j==NY-2){
	udiag_h.x=0.0;
      }

      // Write		

      ldiag[h]=ldiag_h;
      cdiag[h]=cdiag_h;
      udiag[h]=udiag_h;			
	
    }

}



static dim3 threadsPerBlock;
static dim3 blocksPerGrid;


static dim3 threadsPerBlock_B;
static dim3 blocksPerGrid_B;

static cusparseHandle_t hemholzt_handle;

extern void setHemholztDouble(domain_t domain){

  threadsPerBlock.x=NY;
  threadsPerBlock.y=1;

  blocksPerGrid.x=NZ;
  blocksPerGrid.y=NXSIZE/NSTEPS;	

  threadsPerBlock_B.x= THREADSPERBLOCK_IN;
  threadsPerBlock_B.y= THREADSPERBLOCK_IN;

  blocksPerGrid_B.x=NXSIZE/NSTEPS/threadsPerBlock_B.x;
  blocksPerGrid_B.y=NZ*NY/threadsPerBlock_B.y;


  cusparseCheck(cusparseCreate(&hemholzt_handle),domain,"Handle");

}


extern void hemholztSolver_double(float2* u, domain_t domain){
		


  //SIZE OF LDIAG CDIAG UDIAG AND AUX
  //2*SIZE/NSTEPS

  for(int i=0;i<NSTEPS;i++){

    setDiagkernel<<<blocksPerGrid_B,threadsPerBlock_B>>>(LDIAG,CDIAG,UDIAG,i,domain);

    rhs_A_kernel<<<blocksPerGrid,threadsPerBlock>>>(AUX,u+i*NXSIZE/NSTEPS*NZ*NY,domain);
    kernelCheck(RET,domain,"hemholz");	

    cusparseCheck(cusparseZgtsvStridedBatch(hemholzt_handle,NY,LDIAG,CDIAG,UDIAG,AUX,NXSIZE/NSTEPS*NZ,NY),
		  domain,
		  "HEM");

    cast_kernel<<<blocksPerGrid_B,threadsPerBlock_B>>>(u+i*NXSIZE/NSTEPS*NZ*NY,AUX,domain);

  }

  return;
}




