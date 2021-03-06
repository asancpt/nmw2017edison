DATA = Theoph
colnames(DATA) = c("ID", "BWT", "DOSE", "TIME", "DV")
DATA[,"ID"] = as.numeric(as.character(DATA[,"ID"]))

require(lattice)
xyplot(DV ~ TIME | as.factor(ID), data=DATA, type="b")

## INIT STEP
IDs = unique(DATA[,"ID"]) ; IDs
nID = length(IDs) ; nID

nTheta = 3
nEta = 3
nEps = 2
nPara = nTheta + nEta*(nEta + 1)/2 + nEps ; nPara

GNames = outer("G", 1:nEta, paste0)[1,] ; GNames
HNames = outer("H", 1:nEps, paste0)[1,] ; HNames

iOM = (nTheta + 1):(nTheta + nEta*(nEta + 1)/2) ; iOM
iSG = (nTheta + nEta*(nEta + 1)/2 + 1):(nTheta + nEta*(nEta + 1)/2 + nEps) ; iSG

IE = c(2, 50, 0.1)
LB = c(0.2, 5, 0.01)
UB = c(10, 100, 1)

alpha = 0.1 - log((IE - LB)/(UB - LB)/(1 - (IE - LB)/(UB - LB)))

p0 = rep(0.1, nTheta)
p1 = exp(p0 - alpha)
p2 = p1/(p1 + 1)*(UB - LB) + LB ; p2

OM0 = matrix(c(0.2, 0.1, 0.1, 0.1, 0.2, 0.1, 0.1, 0.1, 0.2), nrow=nEta) ; OM0
SG0 = diag(c(0.1, 0.1)) ; SG0

EXPP1 = exp(0.1)
ScaleVar = function(VarMat, dim1)
{
  M1 = chol(VarMat)
  V1 = diag(M1)
  M2 = abs(10 * (M1 - diag(V1, nrow=dim1))) + diag(V1/EXPP1, nrow=dim1)
  return(t(M2))
}

OMscl = ScaleVar(OM0, nEta) ; OMscl
SGscl = ScaleVar(SG0, nEps) ; SGscl

DesclVar = function(mUCP, mSCL)
{
  nRow = dim(mUCP)[1]
  maT = matrix(nrow=nRow, ncol=nRow)

  for (i in 1:nRow) {
    for (j in 1:nRow) {
      if (i==j) {
        maT[i,j] = exp(mUCP[i,j]) * mSCL[i,j]
      } else if(i > j) {
        maT[i,j] = mUCP[i,j] * mSCL[i,j]
      } else {
        maT[i,j] = 0
      }
    }
  }
  return(maT %*% t(maT))
}

DesclVar(matrix(rep(0.1, nEta*nEta), nrow=nEta), OMscl)
DesclVar(diag(rep(0.1, nEps)), SGscl)

ltv2mat = function(vec)
{
  LENGTH = length(vec)
  DIM = round((sqrt(8*LENGTH+1)-1)/2,0)
  if (DIM*(DIM+1)/2 != LENGTH) return(NULL)
  mat = matrix(nrow=DIM, ncol=DIM)
  for (m in 1:DIM) {
    for (n in 1:DIM) {
      k = max(m,n)
      l = min(m,n)
      p = k*(k - 1)/2 + l
      mat[m,n] = vec[p]
    }
  }
  return(mat)
}

s2o = function(p)
{
  p0 = p[1:nTheta]
  p1 = exp(p0 - alpha)
  p2 = p1/(p1 + 1)*(UB - LB) + LB
  OM = DesclVar(ltv2mat(p[iOM]), OMscl)
  SG = DesclVar(diag(p[iSG]), SGscl)
  Res = list(p2, OM, SG)
  names(Res) = c("THETA", "OMEGA", "SIGMA")
  return(Res)
}
s2o(rep(0.1, nPara))

## EST STEP
FGD = deriv(~DOSE/(TH2*exp(ETA2))*TH1*exp(ETA1)/(TH1*exp(ETA1) - TH3*exp(ETA3))*(exp(-TH3*exp(ETA3)*TIME)-exp(-TH1*exp(ETA1)*TIME)),
            c("ETA1","ETA2","ETA3"),
            function.arg=c("TH1", "TH2", "TH3", "ETA1", "ETA2", "ETA3", "DOSE", "TIME"),
            func=TRUE, hessian=TRUE)
H = deriv(~F + F*EPS1 + EPS2, c("EPS1", "EPS2"), function.arg=c("F", "EPS1", "EPS2"), func=TRUE)

PRED = function(THETA, ETA)
{
# External: DATA[,c("ID", "TIME")], cID
  FGDres = FGD(THETA[1], THETA[2], THETA[3], ETA[1], ETA[2], ETA[3], DOSE=320, DATA[DATA$ID==cID,"TIME"])
  Gres = attr(FGDres, "gradient")
  Hres = attr(H(FGDres, 0, 0), "gradient")
  Dres = attr(FGDres, "hessian")
  Res = cbind(FGDres, Gres, Hres, Dres[,1,1], Dres[,2,1], Dres[,2,2], Dres[,3,])
  colnames(Res) = c("F", "G1", "G2", "G3", "H1", "H2", "D11", "D21", "D22", "D31", "D32", "D33")
  return(Res)
}

ObjEta = function(ETA)
{
# External: THETA, invOM, SG, cID, DATA[,"DV"]
  FGH = PRED(THETA, ETA)
  Hi  = FGH[, HNames, drop=FALSE] # always INTER==TRUE
  Ri  = DATA[DATA$ID == cID, "DV"] - FGH[,"F"]

## Slower version
#  Vi = diag(diag(Hi %*% SG %*% t(Hi)))
#  iSum = log(det(Vi)) + t(Ri) %*% solve(Vi) %*% Ri + t(ETA) %*% invOM %*% ETA

## Faster version
  Vi    = diag(Hi %*% SG %*% t(Hi))
  return(sum(log(Vi) + Ri*Ri/Vi) + t(ETA) %*% invOM %*% ETA)
}

EBE = cbind(ID = IDs, ETA1=0, ETA2=0, ETA3=0, Oi=0)

## Preliminary fittting
OBJ2a = function(p)
{
# External: DATA, nTheta, nEta, nEps
  if (STEP == "EST") {
    r     = s2o(p[1:nPara])
    THETA <<- r$THETA      # for ObjEta
    OM    = r$OMEGA
    SG    <<- r$SIGMA      # for ObjEta
  } else {
    THETA <<- p[1:nTheta]  # for ObjEta
    OM    = ltv2mat(p[iOM])
    SG    <<- diag(p[iSG]) # for ObjEta
  }
  invOM <<- solve(OM)      # for ObjEta
  Term3 = determinant(OM, logarithm=TRUE)$modulus[[1]]

  for (i in 1:nID) {
    cID <<- IDs[i] # for PRED
    ETA   = p[(nPara + (i - 1)*nEta + 1):(nPara + i*nEta)]
    FGHDi = PRED(THETA, ETA)
    Gi    = FGHDi[, GNames, drop=FALSE]
    Hi    = FGHDi[, HNames, drop=FALSE] # always INTER==TRUE
    D11   = FGHDi[, "D11"]
    D21   = FGHDi[, "D21"]
    D22   = FGHDi[, "D22"]
    D31   = FGHDi[, "D31"]
    D32   = FGHDi[, "D32"]
    D33   = FGHDi[, "D33"]
    Ri    = DATA[DATA$ID == cID, "DV"] - FGHDi[,"F"]
    Vi    = diag(Hi %*% SG %*% t(Hi))
    Hsum  = invOM + t(Gi) %*% solve(diag(Vi)) %*% Gi
    EBE[i, 2:(1+nEta)] <<- ETA
    EBE[i, (2+nEta)] <<-  sum(log(Vi) + Ri*Ri/Vi) + t(ETA) %*% invOM %*% ETA + Term3 + determinant(Hsum, logarithm=TRUE)$modulus[[1]]
  }
  return(sum(EBE[,5]))
}
STEP = "EST"
OBJ2a(c(rep(0.1, nPara), rep(0, nEta*nID)))

StartTime = Sys.time()
r0 = optim(c(rep(0.1, nPara), rep(0, nEta*nID)), OBJ2a, method="L-BFGS-B")
difftime(Sys.time(), StartTime)
r0
OBJ2a(r0$par)
### END of Preliminary fitting

OBJ2 = function(p)
{
# External: DATA, nTheta, nEta, nEps
  if (STEP == "EST") {
    r     = s2o(p)
    THETA <<- r$THETA      # for ObjEta
    OM    = r$OMEGA
    SG    <<- r$SIGMA      # for ObjEta
  } else {
    THETA <<- p[1:nTheta]  # for ObjEta
    OM    = ltv2mat(p[iOM])
    SG    <<- diag(p[iSG]) # for ObjEta
  }
  invOM <<- solve(OM)      # for ObjEta
  Term3 = determinant(OM, logarithm=TRUE)$modulus[[1]]
  for (i in 1:nID)  {
    cID  <<- i                              # for PRED
    Yi    = DATA[DATA$ID == cID, "DV"]
    TIME  = DATA[DATA$ID == cID, "TIME"]
    Res   = optim(EBE[i,2:(nEta+1)], ObjEta, method="BFGS")
    FGHDi = PRED(THETA, Res$par)
    Fi    = FGHDi[, "F"]
    Gi    = FGHDi[, GNames, drop=FALSE]
    Hi    = FGHDi[, HNames, drop=FALSE]
    D11   = FGHDi[, "D11"]
    D21   = FGHDi[, "D21"]
    D22   = FGHDi[, "D22"]
    D31   = FGHDi[, "D31"]
    D32   = FGHDi[, "D32"]
    D33   = FGHDi[, "D33"]
    Vi    = diag(Hi %*% SG %*% t(Hi))
    Hsum  = invOM
    for (j in 1:length(TIME)) {
      Dij  = matrix(c(D11[j], D21[j], D31[j], D21[j], D22[j], D32[j], D31[j], D32[j], D33[j]), nrow=3)
      Hsum = Hsum + (Gi[j,] %*% t(Gi[j,]) - (Yi[j] - Fi[j])*Dij)/Vi[j]
    }

    EBE[i, 2:4] <<- Res$par
    EBE[i, 5] <<-  Res$value + Term3 + determinant(Hsum, logarithm=TRUE)$modulus[[1]]
  }
  return(sum(EBE[,5]))
}
STEP = "EST"
OBJ2(r0$par[1:nPara]) ; EBE

StartTime = Sys.time()
r0 = optim(r0$par[1:nPara], OBJ2, method="L-BFGS-B")
difftime(Sys.time(), StartTime)
r0
OBJ2(r0$par)

r1 = s2o(r0$par) ; r1

## COV STEP
STEP = "COV"
p = c(r1$THETA, r1$OMEGA[upper.tri(r1$OMEGA, diag=TRUE)], diag(r1$SIGMA))
OBJ2(p)

require(numDeriv)
Rmat = hessian(OBJ2, p)/2 ; Rmat

OiS2 = function(p)
{
  THETA <<- p[1:nTheta]    # for ObjEta
  OM    = ltv2mat(p[iOM])
  invOM <<- solve(OM)      # for ObjEta
  SG    <<- diag(p[iSG])   # for ObjEta
  TIME  = DATA[DATA$ID == cID, "TIME"]
  Yi    = DATA[DATA$ID == cID, "DV"]
  Res   = optim(EBE[EBE[,"ID"]==cID, 2:(nEta+1)], ObjEta, method="BFGS")
  FGHDi = PRED(THETA, Res$par)
  Fi    = FGHDi[, "F"]
  Gi    = FGHDi[, GNames, drop=FALSE]
  Hi    = FGHDi[, HNames, drop=FALSE]
  D11   = FGHDi[, "D11"]
  D21   = FGHDi[, "D21"]
  D22   = FGHDi[, "D22"]
  D31   = FGHDi[, "D31"]
  D32   = FGHDi[, "D32"]
  D33   = FGHDi[, "D33"]
  Vi    = diag(Hi %*% SG %*% t(Hi))

  Hsum  = invOM
  for (j in 1:length(TIME)) {
    Dij = matrix(c(D11[j], D21[j], D31[j], D21[j], D22[j], D32[j], D31[j], D32[j], D33[j]), nrow=3)
    Hsum = Hsum + (Gi[j,] %*% t(Gi[j,]) - (Yi[j] - Fi[j])*Dij)/Vi[j]
  }
  return(Res$value + determinant(OM, logarithm=TRUE)$modulus[[1]] + determinant(Hsum, logarithm=TRUE)$modulus[[1]])
}

CalcSmat = function(p)
{
  Smat = matrix(rep(0, nPara*nPara), nrow=nPara, ncol=nPara)
  for (i in 1:nID) {
    cID <<- i                    # for ObjEta
    gr = grad(OiS2, p)
    Smat = Smat + gr %*% t(gr)
  }
  return(Smat/4)
}

Smat = CalcSmat(p) ; Smat
invR = solve(Rmat) ; invR
Cov = invR %*% Smat %*% invR ; Cov
SE = sqrt(diag(Cov)) ; SE
Correl = cov2cor(Cov) ; Correl
InvCov = Rmat %*% solve(Smat) %*% Rmat ; InvCov
EigenVal = sort(eigen(Correl)$values) ; EigenVal # Sorted Eigenvalues

## EBE
EBE

## sdtab
SqrtInvCov = function(M)
{
  EigenResult = eigen(as.matrix(M))
  EigenVector = EigenResult$vectors
  EigenValues = abs(EigenResult$values)
  return(EigenVector %*% diag(1/sqrt(EigenValues)) %*% t(EigenVector))
}

THETA = r1$THETA
OM = r1$OMEGA
SG = r1$SIGMA
tSD = vector()
for (i in 1:nID) {
  cID  = IDs[i]

  FGH0 = PRED(THETA, rep(0, nEta))
  G0i  = FGH0[, GNames, drop=FALSE]
  H0i  = FGH0[, HNames, drop=FALSE]
  R0i  = DATA[DATA$ID == cID, "DV"] - FGH0[,"F"]
  C0i  = G0i %*% OM %*% t(G0i) + diag(diag(H0i %*% SG %*% t(H0i)))
  WRES = SqrtInvCov(C0i) %*% R0i

  cEBE = EBE[EBE[,"ID"]==cID, 2:(nEta + 1)]
  FGH1 = PRED(THETA, cEBE)
  G1i  = FGH1[, GNames, drop=FALSE]
  H1i  = FGH1[, HNames, drop=FALSE]
  R1i  = DATA[DATA$ID == cID, "DV"] - FGH1[,"F"]
  C1i  = G1i %*% OM %*% t(G1i) + diag(diag(H1i %*% SG %*% t(H1i)))
  CWRES = SqrtInvCov(C1i) %*% (R1i + G1i %*% cEBE)

  tSD = rbind(tSD, cbind(DATA[DATA$ID == cID, c("ID", "TIME", "DV")], PRED=FGH0[,"F"], RES=R0i, WRES, CIPREDI=FGH1[,"F"], CIRESI=R1i, CWRES, G1i, H1i))
} ; tSD

