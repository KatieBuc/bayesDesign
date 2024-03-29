############################ INFO #################################
# - This is a simplified copy of functions from SSN with small fixes
# https://cran.r-project.org/web/packages/SSN/index.html
###################################################################

exp.taildown <- function(dist.hydro, a.mat, b.mat, parsil = parsil, 
                         range1 = range1, useTailDownWeight, weight = NULL)
{
  V <- parsil*exp(-3*dist.hydro/range1)
  if(useTailDownWeight == TRUE) V <- V*weight
  V
}

makeCovMat <-
  function(theta, dist.hydro, a.mat, b.mat, w.matrix = NULL,
           net.zero, x.row, y.row, x.col, y.col, useTailDownWeight,
           CorModels, use.nugget, use.anisotropy, REs)
  {
    
    nRow <- length(x.row)
    nCol <- length(x.col)
    
    if(is.null(net.zero)) net.zero <- matrix(1, nrow = nRow, ncol = nCol)
    V <- matrix(0, nrow = nRow, ncol = nCol)
    
    # create covariance matrix component for tailup models
    npar.sofar <- 0
    if(length(grep("tailup",CorModels)) > 0){
      if(length(grep("tailup",CorModels)) > 1)
        stop("Cannot have more than 1 tailup model")
      funname <- tolower(paste(substr(unlist(strsplit(CorModels,".", 
                                                      fixed = T))[(1:length(unlist(strsplit(CorModels,".", 
                                                                                            fixed = T))))[unlist(strsplit(CorModels,".", fixed = T)) == 
                                                                                                            "tailup"] - 1], 1, 3),".tailup", sep = ""))
      tailupmod <- call(funname, dist.hydro=dist.hydro, 
                        weight = w.matrix, parsil = theta[npar.sofar + 1], 
                        range1 = theta[npar.sofar + 2])
      V <- V + eval(tailupmod)*net.zero
      npar.sofar <- npar.sofar + 2
    }
    # create covariance matrix component for taildown models
    if(length(grep("taildown",CorModels)) > 0){
      if(length(grep("taildown",CorModels)) > 1)
        stop("Cannot have more than 1 taildown model")
      funname <- tolower(paste(substr(unlist(strsplit(CorModels,".", 
                                                      fixed = T))[(1:length(unlist(strsplit(CorModels,".", 
                                                                                            fixed = T))))[unlist(strsplit(CorModels,".", fixed = T)) == 
                                                                                                            "taildown"] - 1], 1, 3),".taildown", sep = ""))
      taildnmod <- call(funname, dist.hydro=dist.hydro, 
                        a.mat = a.mat, b.mat = b.mat, parsil = theta[npar.sofar + 1], 
                        useTailDownWeight = useTailDownWeight, weight = w.matrix,
                        range1 = theta[npar.sofar + 2])
      V <- V + eval(taildnmod)*net.zero
      npar.sofar <- npar.sofar + 2
    }
    # create covariance matrix componenet for Euclidean models
    if(length(grep("Euclid",CorModels)) > 0){
      if(length(grep("Euclid",CorModels)) > 1)
        stop("Cannot have more than 1 Euclidean model")
      npar.parsil <- npar.sofar + 1
      if(use.anisotropy == FALSE) {
        dist.mat <- distGeo(x.row, y.row, x.col, y.col, 
                            theta[npar.sofar + 2])
        npar.sofar <- npar.sofar + 2
      }
      else {
        dist.mat <- distGeo(x.row, y.row, x.col, y.col, 
                            theta[npar.sofar + 2], theta[npar.sofar + 3], 
                            theta[npar.sofar + 4])
        npar.sofar <- npar.sofar + 4
      }
      funname <- paste(tolower(substr(unlist(strsplit(CorModels,".", 
                                                      fixed = T))[(1:length(unlist(strsplit(CorModels,".", 
                                                                                            fixed = T))))[unlist(strsplit(CorModels,".", fixed = T)) == 
                                                                                                            "Euclid"] - 1], 1, 3)),".Euclid", sep = "")
      taileumod <- call(funname, distance.matrix = dist.mat,
                        parsil = theta[npar.parsil])
      V <- V + eval(taileumod)
    }
    
    if(length(REs)) {
      for(ii in 1:length(REs)) {
        npar.sofar <- npar.sofar + 1
        V <- V + theta[npar.sofar]*REs[[ii]]
      }
    }
    
    # create diagonal covariance matrix component for nugget effect
    if(use.nugget == TRUE) {
      if(nRow != nCol) stop(		
        "covariancd matrix asymmetric -- cannot use nugget")
      npar.sofar <- npar.sofar + 1
      V <- V + diag(theta[npar.sofar], nrow = nRow, ncol = nCol)
    } else if(nRow == nCol){
      V + diag(1e-6, nrow = nRow, ncol = nCol)
    }
    
    V
    
  }

SimulateOnSSN_fixed <- function(ssn.object,
                          ObsSimDF,
                          PredSimDF = NULL,
                          PredID = NULL,
                          formula,
                          coefficients,
                          CorModels = c("Exponential.tailup", "Exponential.taildown",
                                        "Exponential.Euclid"),
                          use.nugget = TRUE,
                          use.anisotropy = FALSE,
                          CorParms = c(1,10000,1,10000,1,10000,.1),
                          addfunccol = NULL,
                          useTailDownWeight = FALSE,
                          family = "Gaussian",
                          mean.only = FALSE
)
{
  
  if(tolower(family) != "poisson" & tolower(family) != "binomial" &
     tolower(family) != "gaussian") return("Incorrect family")
  
  data <- ssn.object@obspoints@SSNPoints[[1]]@point.data
  ocoord <- ssn.object@obspoints@SSNPoints[[1]]@point.coords
  nobs <- length(data[,1])	
  
  a.mat <- NULL
  b.mat <- NULL
  net.zero <- NULL
  w.matrix <- NULL
  dist.hydro <- NULL
  xcoord <- NULL
  ycoord <- NULL
  dist.Euclid <- NULL
  distord <- order(data[,"netID"],data[,"pid"])
  names(distord) <- rownames(data)[distord]
  REs <- REPs <- REPPs <- NULL
  
  #-------------------------------------------------------------------------
  #               OBSERVATION BY OBSERVATION COVARIANCE MATRIX
  #-------------------------------------------------------------------------
  if(length(grep("tail",CorModels)) > 0){
    if(length(grep("taildown",CorModels)) > 1)
      stop("Cannot have more than 1 tailup model")
    nets <- levels(ssn.object@data$netID)
    net.count <- length(nets)
    
    dist.junc <- matrix(0, nrow = nobs, ncol = nobs)
    net.zero <-  matrix(0, nrow = nobs, ncol = nobs)
    nsofar <- 0
    nIDs <- sort(unique(data[,"netID"]))
    rnames <- NULL
    for(i in nIDs){
      ind.obs <- ssn.object@obspoints@SSNPoints[[1]]@
        point.data$netID == as.numeric(i)
      site.no <- nrow(ssn.object@obspoints@
                        SSNPoints[[1]]@point.data[ind.obs,])
      if(site.no != 0) {
        workspace.name <- paste("dist.net", i, ".RData", sep = "")
        path <- file.path(ssn.object@path, "distance", "obs", 
                          workspace.name)
        if(!file.exists(path)) {
          stop("Unable to locate required distance matrix")
        }
        file_handle <- file(path, open="rb")
        distmat <- unserialize(file_handle)
        close(file_handle)
        ni <- length(distmat[1,])
        ordwinnet <- order(as.numeric(distord[(nsofar+1):(nsofar+ni)]))
        distmat <- distmat[ordwinnet,ordwinnet, drop = F]
        rnames <- c(rnames, rownames(distmat))
        dist.junc[(nsofar + 1):(nsofar + ni),(nsofar + 1):
                    (nsofar + ni)] <- distmat
        net.zero[(nsofar + 1):(nsofar + ni),(nsofar + 1):
                   (nsofar + ni)] <- 1
        nsofar <- nsofar + ni
      }
    }
    if(any(rnames != as.numeric(data[distord,"pid"])))
      stop("problem with data/distance-matrix ordering")
    rownames(dist.junc) <- rnames
    # maximum distance to common junction between two sites
    a.mat <- pmax(dist.junc,t(dist.junc))
    # minimum distance to common junction between two sites
    b.mat <- pmin(dist.junc,t(dist.junc))
    # hydrological distance
    dist.hydro <- as.matrix(dist.junc + t(dist.junc))*net.zero
    if(length(grep("tailup",CorModels)) > 0){
      if(length(grep("tailup",CorModels)) > 1)
        stop("Cannot have more than 1 tailup model")
      flow.con.mat <- 1 - (b.mat > 0)*1			
      w.matrix <- sqrt(pmin(outer(data[distord,addfunccol],rep(1, times = nobs)),
                            t(outer(data[distord,addfunccol],rep(1, times = nobs)))) /
                         pmax(outer(data[distord,addfunccol],rep(1, times = nobs)),
                              t(outer(data[distord,addfunccol],rep(1, times = nobs))))) *
        flow.con.mat*net.zero
    }
    
  }
  xcoord <- ocoord[distord,1, drop = F]
  ycoord <- ocoord[distord,2, drop = F]
  
  
  if(any(ObsSimDF[distord,"pid"] != data[distord,"pid"]))
    stop("ObsSimDF must have same ordering by pid as ...@SSNPoints[[1]]@point.data")
  REs <- NULL
  REind <- which(names(ObsSimDF) %in% CorModels)
  if(length(REind)) {
    for(ii in REind) if(any(is.na(ObsSimDF[,ii])))
      stop("Cannot having missing values when creating random effects")
    REs <- list()
    REnames <- sort(names(ObsSimDF)[REind])
    ## model matrix for a RE factor
    for(ii in 1:length(REind)) REs[[ii]] <- 
      model.matrix(~ObsSimDF[distord,REnames[ii]] - 1)
    ## corresponding block matrix 
    for(ii in 1:length(REind)) REs[[ii]] <- REs[[ii]] %*% t(REs[[ii]])
  }
  
  CovMat <- makeCovMat(theta = CorParms, dist.hydro, a.mat, b.mat, w.matrix,
                       net.zero, xcoord, ycoord, xcoord, ycoord, useTailDownWeight, CorModels,
                       use.nugget, use.anisotropy, REs)
  V <- CovMat
  
  #-------------------------------------------------------------------------
  #               CHECK COVARIANCE PARAMETERS
  #-------------------------------------------------------------------------
  terms <- NULL
  type <- NULL
  if(length(grep("tailup", CorModels)) > 0){
    type <- c(type, c("parsill","range"))
    terms <- c(terms, rep(CorModels[grep("tailup", CorModels)], 
                          times = 2))
  }
  if(length(grep("taildown",CorModels)) > 0){
    type <- c(type, c("parsill", "range"))
    terms <- c(terms, rep(CorModels[grep("taildown", CorModels)], 
                          times = 2))
  }
  if(length(grep("Euclid",CorModels)) > 0){
    if(use.anisotropy == FALSE) {
      type <- c(type, c("parsill", "range"))
      terms <- c(terms,rep(CorModels[grep("Euclid", CorModels)], 
                           times = 2))
    } else {
      type <- c(type, c("parsill", "range", "axratio", "rotate"))
      terms <- c(terms,rep(CorModels[grep("Euclid", CorModels)], 
                           times = 4))
    }
  }
  if(length(REind)) {
    type = c(type, rep("parsill", times = length(REind)))
    terms <- c(terms, REnames)
  }
  if(use.nugget) {
    type = c(type, "parsill")
    terms <- c(terms, "nugget")
  }
  if(length(terms) != length(CorParms)) {
    CPdf <- data.frame(terms=terms, type = type)
    print("Number of CorParms not correct based on CorModels specification")
    print("Named correlation parameters, in order, needing values")
    print(CPdf)
    stop()
  }
  
  #-------------------------------------------------------------------------
  #               IF SIMULATING PREDICTIONS
  #-------------------------------------------------------------------------
  
  if(!is.null(PredSimDF)) {
    
    #get the predicted data data.frame and coordinates from glmssn object
    for(i in 1:length(ssn.object@predpoints@SSNPoints))
      if(ssn.object@predpoints@ID[i] == PredID){
        datap <- ssn.object@predpoints@
          SSNPoints[[i]]@point.data
        pcoord <- ssn.object@predpoints@
          SSNPoints[[i]]@point.coords
        netpcoord <- ssn.object@predpoints@
          SSNPoints[[i]]@network.point.coords
      }	  
    npred <- length(datap[,1])
    distordp <- order(as.integer(as.character(datap[,"netID"])),
                      datap[,"pid"])
    datap <- datap[distordp, , drop = F]
    pcoord <- pcoord[distordp, , drop = F]
    netpcoord <- netpcoord[distordp, , drop = F]
    
    #---------------------------------------------------------------------
    #               OBSERVATION BY PREDICTION COVARIANCE MATRIX
    #---------------------------------------------------------------------
    x.pred <- NULL
    y.pred <- NULL
    x.samp <- NULL
    y.samp <- NULL
    if(length(grep("tail",CorModels)) > 0){
      nets <- levels(ssn.object@data$netID)
      net.count <- length(nets)					  
      dist.junc.a <- matrix(0, nrow = nobs, ncol = npred)
      dist.junc.b <- matrix(0, nrow = npred, ncol = nobs)
      net.zero <-  matrix(0, nrow = nobs, ncol = npred)
      nSoFari <- 0
      nSoFarj <- 0
      nIDs <- sort(unique(c(as.integer(as.character(data[,"netID"])),
                            as.integer(as.character(datap[,"netID"])))))
      #loop through the networks to build covariance matrix
      for(i in nIDs) {
        ind.obs <- ssn.object@obspoints@SSNPoints[[1]]@
          point.data$netID == as.numeric(i)
        site.no <- nrow(ssn.object@obspoints@SSNPoints[[1]]@
                          point.data[ind.obs,])
        ind.pred <- datap$netID == as.numeric(i)
        pred.no <- nrow(datap[ind.pred,])
        if(site.no*pred.no != 0) {				  
          workspace.name.a <- paste("dist.net", i,
                                    ".a.RData", sep = "")
          workspace.name.b <- paste("dist.net", i, 
                                    ".b.RData", sep = "")				  
          path.a <- file.path(ssn.object@path, 
                              "distance", PredID, workspace.name.a)
          path.b <- file.path(ssn.object@path, 
                              "distance", PredID, workspace.name.b)				  
          # distance matrix a
          file_handle = file(path.a, open="rb")
          distmata <- unserialize(file_handle)
          close(file_handle)				  
          # distance matrix b
          file_handle = file(path.b, open="rb")
          distmatb <- unserialize(file_handle)
          close(file_handle)				  
          # pid's for observed data in matrices above
          ordoi <- order(as.numeric(rownames(distmata)))
          ordpi <- order(as.numeric(rownames(distmatb)))
          ni <- length(ordoi)
          nj <- length(ordpi)
          distmata <- distmata[ordoi, ordpi, drop = F]
          distmatb <- distmatb[ordpi, ordoi, drop = F]
          dist.junc.a[(nSoFari + 1):(nSoFari + ni),
                      (nSoFarj + 1):(nSoFarj + nj)] <- distmata
          dist.junc.b[(nSoFarj + 1):(nSoFarj + nj),
                      (nSoFari + 1):(nSoFari + ni)] <- distmatb
          net.zero[(nSoFari + 1):(nSoFari + ni),
                   (nSoFarj + 1):(nSoFarj + nj)] <- 1
        } else {
          ni <- sum(as.integer(as.character(
            data[,"netID"])) == i)
          nj <- sum(as.integer(as.character(
            datap[,"netID"])) == i)
        }
        nSoFari <- nSoFari + ni
        nSoFarj <- nSoFarj + nj
      }
      # creat A matrix (longest distance to junction of two points)
      a.mat <- pmax(dist.junc.a,t(dist.junc.b))
      # creat B matrix (shorted distance to junction of two points)
      b.mat <- pmin(dist.junc.a,t(dist.junc.b))
      # get hydrologic distance
      dist.hydro <- as.matrix(dist.junc.a + t(dist.junc.b))		  
      # create indicator matrix of flow-connected
      if(length(grep("tailup",CorModels)) > 0){
        flow.con.mat <- 1 - (b.mat > 0)*1
        # weight matrix based on additive function
        w.matrix <- sqrt(pmin(outer(data[distord,addfunccol],
                                    rep(1, times = npred)),
                              t(outer(datap[,addfunccol],rep(1, times = nobs)))) /
                           pmax(outer(data[distord,addfunccol],
                                      rep(1, times = npred)),
                                t(outer(datap[,addfunccol],rep(1, times = nobs))))) *
          flow.con.mat*net.zero
      }	
    }    	
    xyobs <- ocoord[distord, ]
    x.samp <- ocoord[distord,1,drop = F]
    y.samp <- ocoord[distord,2,drop = F]
    xypred <- pcoord
    x.pred <- pcoord[,1,drop = F]
    y.pred <- pcoord[,2,drop = F]	
    REPs <- NULL  
    REPind <- which(names(PredSimDF) %in% CorModels)
    if(length(REPind)) {
      for(ii in REPind) if(any(is.na(PredSimDF[,ii])))
        stop("Cannot having missing values when creating random effects")
    }
    REs <- list()
    REnames <- sort(names(ObsSimDF)[REind])
    if(length(REind)) {
      for(ii in REind) if(any(is.na(PredSimDF[,ii])))
        stop("Cannot having missing values when creating random effects")
      REOs <- list()
      REPs <- list()
      ## model matrix for a RE factor
      for(ii in 1:length(REind)){ 
        #we'll add "o" to observed levels and "p" to prediction
        # levels so create all possible levels
        plevels <- unique(c(levels(PredSimDF[,REnames[[ii]]]),
                            paste("o",levels(ObsSimDF[,REnames[[ii]]]),sep = ""),
                            paste("p",levels(PredSimDF[,REnames[[ii]]]),sep = "")))
        # sites with prediction levels same as observation levels
        pino <- PredSimDF[,REnames[[ii]]] %in% ObsSimDF[,REnames[[ii]]]
        #add "o" to observed levels
        ObsSimDF[,REnames[[ii]]] <- paste("o", 
                                          ObsSimDF[,REnames[[ii]]], sep = "")
        ObsSimDF[,REnames[[ii]]] <- as.factor(as.character(
          ObsSimDF[,REnames[[ii]]]))
        #add all possible levels to prediction data frame
        levels(PredSimDF[,REnames[[ii]]]) <- plevels
        # add "o" to prediction sites with observation levels
        if(any(pino)) PredSimDF[pino,REnames[[ii]]] <- paste("o", 
                                                             PredSimDF[pino,REnames[[ii]]], sep = "")
        # add "p" to all predicition sites without observation levels
        if(any(!pino)) PredSimDF[!pino,REnames[[ii]]] <- paste("p", 
                                                               PredSimDF[!pino,REnames[[ii]]], sep = "")
        PredSimDF[,REnames[[ii]]] <- as.factor(as.character(
          PredSimDF[,REnames[[ii]]]))
        # now get down to just levels with "o" & "p" added
        blevels <- unique(c(levels(ObsSimDF[,REnames[[ii]]]),
                            levels(PredSimDF[,REnames[[ii]]])))
        ObsSimDF[,REnames[[ii]]] <- factor(ObsSimDF[,REnames[[ii]]],
                                           levels = blevels, ordered = FALSE)
        PredSimDF[,REnames[[ii]]] <- factor(PredSimDF[,REnames[[ii]]],
                                            levels = blevels, ordered = FALSE)
        # now ordering of factors in Z matrices should be compatible
        # with obs x obs Z matrices
        REOs[[ii]] <- model.matrix(~ObsSimDF[distord,
                                             REnames[[ii]]] - 1)
        REPs[[ii]] <- model.matrix(~PredSimDF[distordp,
                                              REnames[[ii]]] - 1)
      }
      ## corresponding block matrix 
      for(ii in 1:length(REind)) REPs[[ii]] <- 
        REOs[[ii]] %*% t(REPs[[ii]])
    }
    Vpred <- makeCovMat(theta = CorParms, dist.hydro = dist.hydro,
                        a.mat = a.mat, b.mat = b.mat, w.matrix = w.matrix,
                        net.zero = net.zero, x.row = x.samp, y.row = y.samp,
                        x.col = x.pred, y.col = y.pred, useTailDownWeight = useTailDownWeight,
                        CorModels = CorModels, use.nugget = FALSE,
                        use.anisotropy = FALSE, REs = REPs)
    
    #---------------------------------------------------------------------
    #               PREDICTION BY PREDICTION COVARIANCE MATRIX
    #---------------------------------------------------------------------
    a.mat <- NULL
    b.mat <- NULL
    net.zero <- NULL
    w.matrix <- NULL
    dist.hydro <- NULL
    xcoordp <- NULL
    ycoordp <- NULL
    dist.Euclid <- NULL
    if(length(grep("tail",CorModels)) > 0){
      nets <- levels(datap$netID)
      net.count <- length(nets)		  
      dist.junc <- matrix(0, nrow = npred, ncol = npred)
      net.zero <-  matrix(0, nrow = npred, ncol = npred)
      nsofar <- 0
      nIDs <- as.integer(as.character(sort(unique(datap[,"netID"]))))
      for(i in nIDs){
        ind.pred <- datap$netID == as.numeric(i)
        pred.no <- nrow(datap[ind.pred,])
        if(pred.no != 0) {
          workspace.name <- paste("dist.net", i, 
                                  ".RData", sep = "")
          path <- file.path(ssn.object@path, "distance", 
                            PredID, workspace.name)
          if(!file.exists(path)) {
            stop("Unable to locate required distance matrix")
          }
          file_handle <- file(path, open="rb")
          distmat <- unserialize(file_handle)
          close(file_handle)
          ni <- length(distmat[1,])
          ordpi <- order(as.numeric(rownames(distmat)))
          dist.junc[(nsofar + 1):(nsofar + ni),(nsofar + 1):
                      (nsofar + ni)] <- distmat[ordpi, ordpi, drop = F]
          net.zero[(nsofar + 1):(nsofar + ni),(nsofar + 1):
                     (nsofar + ni)] <- 1
          nsofar <- nsofar + ni
        }
      }
      # maximum distance to common junction between two sites
      a.mat <- pmax(dist.junc,t(dist.junc))
      # minimum distance to common junction between two sites
      b.mat <- pmin(dist.junc,t(dist.junc))
      # hydrological distance
      dist.hydro <- as.matrix(dist.junc + t(dist.junc))*net.zero
      if(length(grep("tailup",CorModels)) > 0){
        flow.con.mat <- 1 - (b.mat > 0)*1			
        w.matrix <- sqrt(pmin(outer(datap[,addfunccol],
                                    rep(1, times = npred)),
                              t(outer(datap[,addfunccol],rep(1, times = npred)))) /
                           pmax(outer(datap[,addfunccol],rep(1, times = npred)),
                                t(outer(datap[,addfunccol],rep(1, times = npred))))) *
          flow.con.mat*net.zero
      }		  
    }
    xcoordp <- pcoord[, 1, drop = F]
    ycoordp <- pcoord[, 2, drop = F]
    REPPs <- NULL	  
    if(length(REind)) {
      REPPs <- list()
      ## model matrix for a RE factor
      for(ii in 1:length(REind)) REPPs[[ii]] <- 
          model.matrix(~PredSimDF[distordp,REnames[ii]] - 1)
      ## corresponding block matrix 
      for(ii in 1:length(REind)) REPPs[[ii]] <- 
          REPPs[[ii]] %*% t(REPPs[[ii]])
    }
    CovMatp <- makeCovMat(theta = CorParms, dist.hydro, 
                          a.mat, b.mat, w.matrix, net.zero, xcoordp, ycoordp, 
                          xcoordp, ycoordp, useTailDownWeight, CorModels, use.nugget, use.anisotropy,
                          REPPs)
    V <- rbind(cbind(CovMat,Vpred), cbind(t(Vpred), CovMatp))
  }  
  
  #---------------------------------------------------------------------
  #               SIMULATE DATA
  #---------------------------------------------------------------------
  
  SimDF <- ObsSimDF[distord,]
  if(!is.null(PredSimDF)) SimDF <- rbind(SimDF, PredSimDF[distordp,])
  SimDF[,"Sim_Values"] <- rep(1, times = length(SimDF[,1]))
  formula1 <- as.formula(paste("Sim_Values", as.character(formula)[1], 
                               as.character(formula)[2]))
  mf <- model.frame(formula1, data = SimDF)
  mt <- attr(mf, "terms")
  X1 <- model.matrix(mt, mf)
  nsim <- length(X1[,1])
  if(length(X1[1,]) != length(coefficients)) {
    print("Number of coefficients not correct based on formula specification")
    print("Named column order needing coefficients")
    print(colnames(X1))
    stop()
  }
  sim.mean <- X1 %*% coefficients
  eigV <- eigen(V)
  if(any(eigV$values <= 0)) 
    stop("Negative eigenvalues in covariance matrix")
  # Square root of covariance matrix
  svdV.5 <- eigV$vectors %*% diag(sqrt(eigV$values)) %*% t(eigV$vectors)
  SimValues <- sim.mean + 
    svdV.5 %*% rnorm(nsim, 0, 1)
  svo <- SimValues[1:length(distord),,drop = F]
  if(family == "Poisson" | family == "poisson") {
    if(mean.only) {
      svo[,1] <- round(exp(svo[,1]))} else 
      {
        svo[,1] = rpois(length(svo[,1]), exp(svo[,1]))}
  }
  if(family == "Binomial" | family == "binomial") {
    if(mean.only) {
      svo[,1] <- round(exp(svo[,1])/
                         (1 + exp(svo[,1])))} else
                         {
                           svo[,1] <- rbinom(length(svo[,1]),1,exp(svo[,1])/
                                               (1 + exp(svo[,1])))}
  }
  if(any(rownames(svo[order(distord),,drop = F]) != data[,"pid"]))
    stop("Simulated vector is in the wrong order")
  ObsSimDF[,"Sim_Values"] <- as.vector(svo[order(distord),,drop = F])
  if(!is.null(PredSimDF)) {
    svp <- SimValues[(length(distord)+1):(length(distord) + 
                                            length(distordp)),,drop = F]
    if(tolower(family) == "poisson") 
      svp[,1] = rpois(length(svp[,1]), exp(svp[,1]))
    if(tolower(family) == "binomial") 
      svp[,1] <- rbinom(length(svp[,1]), 1,
                        exp(svp[,1])/(1 + exp(svp[,1])))
    PredSimDF[,"Sim_Values"] <- as.vector(svp[order(distordp),,drop = F])
    for(i in 1:length(ssn.object@predpoints@SSNPoints))
      if(ssn.object@predpoints@ID[i] == PredID){
        if(any(rownames(svp[order(distordp),,drop = F]) != 
               ssn.object@predpoints@SSNPoints[[i]]@point.data[,"pid"]))
          stop("Simulated prediction vector is in the wrong order")
        if(any(ssn.object@predpoints@SSNPoints[[i]]@
               point.data[,"pid"] != PredSimDF[,"pid"]))
          stop("PredSimDF order does not match original data")
        ssn.object@predpoints@SSNPoints[[i]]@point.data <- PredSimDF
      }
  }
  if(any(ssn.object@obspoints@SSNPoints[[1]]@point.data[,"pid"] != 
         ObsSimDF[,"pid"]))
    stop("ObsSimDF order does not match original data")
  ssn.object@obspoints@SSNPoints[[1]]@point.data <- ObsSimDF
  XnameCoef <- data.frame(Xnames = colnames(X1), Coefficient = coefficients)
  CovParms <- data.frame(CorModel = terms, type = type, Parameter = CorParms)
  
  list(ssn.object = ssn.object, FixedEffects = XnameCoef,
       CorParms = CovParms)
  
}

#' The systematicDesign function from SSN updated to be compatible with functions from SSNDesign
#' 
#'@description
#'
#'\code{systematicDesign} replaces a function of the same name from the package SSN. This version of the function can be used with \code{generateSites}.
#'
#'@inheritParams systematicDesign
#'@return Result not seen by user.
#'
#'@details
#'
#'This function was written to deal with errors resulting in the \code{systematicDesign} function from the package SSN when it was used with SpatialStreamNetworks built from real spatial data. It is back-compatible with the \code{createSSN} function from SSN.
#' 
#' @export
systematicDesign2 <- function(spacing, replications = 1, rep.variable = "Time", rep.values) {
  if (missing(rep.values)) 
    rep.values <- 1:replications
  if (replications != length(rep.values)) {
    stop("Input rep.values must contain one element for each replication")
  }
  design.function <- function(tree.graphs, edge_lengths, locations, 
                              edge_updist, distance_matrices) {
    if (length(spacing) == 1) 
      spacing <- rep(spacing, length(tree.graphs))
    if (length(spacing) != length(tree.graphs)) {
      stop("Dimension mismatch: Input spacing must contain one number, or one number for each network")
    }
    n_networks <- length(tree.graphs)
    result <- vector(mode = "list", length = length(n_networks))
    cumulative_locID <- 0
    for (netid in 1:n_networks) {
      spacing_this_network <- spacing[netid]
      graph <- tree.graphs[[netid]]
      edge_lengths_this_network <- edge_lengths[[netid]]
      rids <- names(edge_updist[[netid]])
      edges_this_network <- get.edgelist(graph)
      points_this_network <- sort(unique(as.numeric(edges_this_network)))
      positions_per_segment <- vector(mode = "list", length = length(edge_lengths_this_network))
      done_points <- !(points_this_network %in% edges_this_network[, 2])
      done_segments <- c()
      segment_remaining <- c()
      while (length(done_segments) != nrow(edges_this_network)) {
        can_calculate <- done_points[match(edges_this_network[, 1], points_this_network)]
        can_calculate[done_segments] <- FALSE
        can_calculate_indices <- which(can_calculate)
        if (!any(can_calculate)) 
          stop("Internal error")
        for (index in can_calculate_indices) {
          edge <- edges_this_network[index, ]
          remaining <- segment_remaining[match(match(edge[1], edges_this_network[, 2]), done_segments)]
          if (is.null(remaining)) 
            remaining <- spacing_this_network
          if(is.na(remaining))
            remaining <- spacing_this_network
          edge_length <- edge_lengths_this_network[index]
          
          
          #print(edge_length)
          #print(remaining)
          #print(spacing_this_network)
          if (edge_length + remaining < spacing_this_network) {
            segment_remaining <- c(segment_remaining, 
                                   edge_length + remaining)
          }
          else {
            positions_per_segment[[index]] <- seq(spacing_this_network - 
                                                    remaining, edge_length, by = spacing_this_network)
            segment_remaining <- c(segment_remaining, 
                                   edge_length - max(positions_per_segment[[index]]))
          }
          done_segments <- c(done_segments, index)
          done_points[match(edge[2], points_this_network)] <- TRUE
        }
      }
      proportions_per_segment <- positions_per_segment
      for (i in 1:length(proportions_per_segment)) proportions_per_segment[[i]] <- proportions_per_segment[[i]]/edge_lengths_this_network[i]
      unreplicated <- data.frame(edge = rep(rids, times = unlist(lapply(proportions_per_segment, 
                                                                        length))), ratio = unlist(proportions_per_segment), 
                                 stringsAsFactors = FALSE)
      unreplicated$locID <- 1:nrow(unreplicated) + cumulative_locID
      cumulative_locID <- cumulative_locID + nrow(unreplicated)
      result[[netid]] <- unreplicated
    }
    return(result)
  }
  return(replication.function(design.function, replications, 
                                    rep.variable, rep.values))
}

