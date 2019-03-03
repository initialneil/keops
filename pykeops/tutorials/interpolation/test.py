

import numpy as np
import torch
from pykeops.torch import Genred 

from pykeops.tutorials.interpolation.torch.linsolve import InvKernelOp

def GaussKernel(D,Dv,sigma):
    formula = 'Exp(-oos2*SqDist(x,y))*b'
    variables = ['x = Vx(' + str(D) + ')',  # First arg   : i-variable, of size D
                 'y = Vy(' + str(D) + ')',  # Second arg  : j-variable, of size D
                 'b = Vy(' + str(Dv) + ')',  # Third arg  : j-variable, of size Dv
                 'oos2 = Pm(1)']  # Fourth arg  : scalar parameter
    my_routine = Genred(formula, variables, reduction_op='Sum', axis=1)
    oos2 = torch.Tensor([1.0/sigma**2])
    def K(x,y,b):
        return my_routine(x,y,b,oos2)
    return K

def InvGaussKernel(D,Dv,sigma):
    formula = 'Exp(-oos2*SqDist(x,y))*b'
    variables = ['x = Vx(' + str(D) + ')',  # First arg   : i-variable, of size D
                 'y = Vy(' + str(D) + ')',  # Second arg  : j-variable, of size D
                 'b = Vy(' + str(Dv) + ')',  # Third arg  : j-variable, of size Dv
                 'oos2 = Pm(1)']  # Fourth arg  : scalar parameter
    my_routine = InvKernelOp(formula, variables, 'b', axis=1)
    oos2 = torch.Tensor([1.0/sigma**2])
    def Kinv(x,b):
        return my_routine(x,x,b,oos2)
    return Kinv

def GaussKernelMatrix(sigma):
    oos2 = 1.0/sigma**2
    def f(x,y):
        D = x.shape[1]
        sqdist = 0
        for k in range(D):
            sqdist += (x[:,k][:,None]-(y[:,k][:,None]).t())**2
        return torch.exp(-oos2*sqdist)
    return f

arraysum = lambda a : torch.dot(a.view(-1), torch.ones_like(a).view(-1))
grad = torch.autograd.grad

        
D = 2
N = 4
sigma = .1
x = torch.rand(N, D, requires_grad=True)
b = torch.rand(N, D)
Kinv = InvGaussKernel(D,D,sigma)
c = Kinv(x,b)
print("c = ",c)

from torchviz import make_dot
make_dot(c).save("ess.dot")

e = torch.randn(N,D)
u, = grad(c,x,e,create_graph=True)
print("u=",u)

make_dot(u).save("ess2.dot")

###

xx = x.clone()
bb = b.clone()
MM = GaussKernelMatrix(sigma)(xx,xx)
cc = torch.gesv(bb,MM)[0].contiguous()
uu, = grad(cc,xx,e,create_graph=True)
print("uu=",uu)   

 

###


xxx = x.clone()
bbb = b.clone()
MMM= GaussKernelMatrix(sigma)(xxx,xxx)
MMMi = torch.inverse(MMM)
ccc = MMMi@bbb
uuu, = grad(ccc,xxx,e,create_graph=True)
print("uuu=",uuu)  

###

xxxx = x.clone()
bbbb = b.clone()
MMMM= GaussKernelMatrix(sigma)(xxxx,xxxx)
MMMMi = torch.inverse(MMMM)
cccc = MMMMi@bbbb
uuuu = grad(cccc,xxxx,e)[0]
print("uuuu=",uuuu)  


print("2nd order derivative")

e = torch.randn(N,D)
v = grad(u,x,e,create_graph=True)[0]
print("v=",v)


ee = e.clone()
vv = grad(uu,xx,ee,create_graph=True)[0]
print("vv=",vv)

eee = e.clone()
vvv = grad(uuu,xxx,eee,create_graph=True)[0]
print("vvv=",vvv)
print(torch.norm(v-vv))
print(torch.norm(vv-vvv))

print("3rd order derivative")


e = torch.randn(N,D)
w = grad(v,x,e,create_graph=True)[0]
print("w=",w)


ee = e.clone()
ww = grad(vv,xx,ee)[0]
print("ww=",ww)

eee = e.clone()
www = grad(vvv,xxx,eee)[0]
print("www=",www)
print(torch.norm(w-ww))
print(torch.norm(ww-www))

