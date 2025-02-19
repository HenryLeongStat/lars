lars <-
function(x, y, type = c("lasso", "lar", "forward.stagewise","stepwise"), trace = FALSE,
           normalize=TRUE, intercept=TRUE, Gram, 
           eps = 1e-12,  max.steps, use.Gram = TRUE)
{
### program automatically centers and standardizes predictors by default.
###
### Original program by Brad Efron September 2001
### Recoded by Trevor Hastie November 2001
### Computational efficiency December 22, 2001
### Bug fixes and singularities February 2003
### Conversion to R April 2003
### stepwise and non-standardize options added May 2007
### Copyright Brad Efron and Trevor Hastie
  call <- match.call()
  type <- match.arg(type)
  TYPE <- switch(type,
                 lasso = "LASSO",
                 lar = "LAR",
                 forward.stagewise = "Forward Stagewise",
                 stepwise = "Forward Stepwise")
  if(trace)
    cat(paste(TYPE, "sequence\n"))
  
  nm <- dim(x)
  n <- nm[1]
  m <- nm[2]
  im <- inactive <- seq(m) # indices from 1 to p
  one <- rep(1, n)
  vn <- dimnames(x)[[2]]	
### Center x and y, and scale x, and save the means and sds
  # never deal with intercept!
  if(intercept){
    meanx <- drop(one %*% x)/n
    x <- scale(x, meanx, FALSE)	# centers x to remove intercept
    mu <- mean(y)
    y <- drop(y - mu)
  }
  else {
    meanx <- rep(0,m)
    mu <- 0
    y <- drop(y)
  }
  if(normalize){
    normx <- sqrt(drop(one %*% (x^2)))
    nosignal<-normx/sqrt(n) < eps
    if(any(nosignal))# ignore variables with too small a variance
      {
        ignores<-im[nosignal]
        inactive<-im[-ignores]
        normx[nosignal]<-eps*sqrt(n)
        if(trace)
          cat("LARS Step 0 :\t", sum(nosignal), "Variables with Variance < eps; dropped for good\n")	#
      }
    else ignores <- NULL #singularities; augmented later as well
    names(normx) <- NULL
    x <- scale(x, FALSE, normx)	# scales x
  }
  else {
    normx <- rep(1,m)
    ignores <- NULL
  }
  if(use.Gram & missing(Gram)) {
    if(m > 500 && n < m)
      cat("There are more than 500 variables and n<m;\nYou may wish to restart and set use.Gram=FALSE\n"
          )
    if(trace)
      cat("Computing X'X .....\n")
    Gram <- t(x) %*% x	#Time saving
  }
  Cvec <- drop(t(y) %*% x) ## initialization
  ssy <- sum(y^2)	### Some initializations
  residuals <- y ## initialization
  if(missing(max.steps))
    max.steps <- 8*min(m, n-intercept) # intercept is logical
  beta <- matrix(0, max.steps + 1, m)	# beta starts at 0 # last one is the lm fit
  lambda=double(max.steps) # a vector for saving the lambda at each step
  Gamrat <- NULL
  arc.length <- NULL # save all gamma_hat
  R2 <- 1
  RSS <- ssy
  first.in <- integer(m) # a m-vector of integer, the step of the corresponding variable to be first time in the model
  active <- NULL	# maintains active set
  actions <- as.list(seq(max.steps))	
                                        # a signed index list to show what comes in and out
  drops <- FALSE	# to do with type=="lasso" or "forward.stagewise"
  Sign <- NULL	# Keeps the sign of the terms in the model, # 2.10
  R <- NULL	### choleski R  of X[,active] 
### Now the main loop over moves
###
  k <- 0
  # when entering the loop, active is null, => length=0
  while((k < max.steps) & (length(active) < min(m - length(ignores),n-intercept)) )
    {
      action <- NULL
      C <- Cvec[inactive]	# 2.8
### identify the largest nonactive gradient
      Cmax <- max(abs(C)) # 2.9
      if(Cmax<eps*100){ # the 100 is there as a safety net
        if(trace)cat("Max |corr| = 0; exiting...\n")
        break
      }
      k <- k + 1
      lambda[k]=Cmax # save the max C from each step
### Check if we are in a DROP situation
      if(!any(drops)) { # when without drops for all
        new <- abs(C) >= Cmax - eps # see how many correlations are effectively equal to the max one
        C <- C[!new]	# for later, # remove the ones meeting the above critieria
        new <- inactive[new]	# Get index numbers, # get the ones got removed above
        # => new is the set that the correlation of which are effectively equal to the max one
        # and the elements of this set will be added in this step
### We keep the choleski R  of X[,active] (in the order they enter)
        for(inew in new) {
          if(use.Gram) {
            R <- updateR(Gram[inew, inew], R, drop(Gram[
                                                        inew, active]), Gram = TRUE,eps=eps)
          }
          else {
            R <- updateR(x[, inew], R, x[, active], Gram
                         = FALSE,eps=eps)
          }
          if(attr(R, "rank") == length(active)) {
            ##singularity; back out
            nR <- seq(length(active))
            R <- R[nR, nR, drop = FALSE]
            attr(R, "rank") <- length(active)
            ignores <- c(ignores, inew)
            action <- c(action,  - inew)
            if(trace)
              cat("LARS Step", k, ":\t Variable", inew, 
                  "\tcollinear; dropped for good\n")	#
          }
          else {
            if(first.in[inew] == 0)
              first.in[inew] <- k
            active <- c(active, inew) # add the new variable to the active set
            Sign <- c(Sign, sign(Cvec[inew])) # 2.10 # get the sign from the correlation vector
            action <- c(action, inew) # add the new variable in the current action set in the loop, it gets empty every iteration
            if(trace)
              cat("LARS Step", k, ":\t Variable", inew, 
                  "\tadded\n")	#
          }
        }
      }
      # end of if(!any(drops))
      else action <-  - dropid # corresponding to if(!any(drops))
      # if there are any drops, then the action set will be the drop elements
      Gi1 <- backsolve(R, backsolvet(R, Sign)) # 2.5 Gi%*%one
### Now we have to do the forward.stagewise dance
### This is equivalent to NNLS
      dropouts<-NULL
      if(type == "forward.stagewise") {
        directions <- Gi1 * Sign
        if(!all(directions > 0)) {
          if(use.Gram) {
            nnls.object <- nnls.lars(active, Sign, R, 
                                     directions, Gram[active, active], trace = 
                                     trace, use.Gram = TRUE,eps=eps)
          }
          else {
            nnls.object <- nnls.lars(active, Sign, R, 
                                     directions, x[, active], trace = trace, 
                                     use.Gram = FALSE,eps=eps)
          }
          positive <- nnls.object$positive
          dropouts <-active[-positive]
          action <- c(action, -dropouts)
          active <- nnls.object$active
          Sign <- Sign[positive]
          Gi1 <- nnls.object$beta[positive] * Sign
          R <- nnls.object$R
          C <- Cvec[ - c(active, ignores)]
        }
      }
      # end of forward.stagewise
      A <- 1/sqrt(sum(Gi1 * Sign)) # 2.5
      w <- A * Gi1	# 2.6 # note that w has the right signs
      if(!use.Gram) u <- drop(x[, active, drop = FALSE] %*% w) # 2.6	###
### Now we see how far we go along this direction before the
### next competitor arrives. There are several cases
###
### If the active set is all of x, go all the way
      if( (length(active) >=  min(n-intercept, m - length(ignores) ) )|type=="stepwise") {
        gamhat <- Cmax/A
      }
      else {
        if(use.Gram) {
          a <- drop(w %*% Gram[active,  - c(active,ignores), drop = FALSE])
        }
        else {
          a <- drop(u %*% x[,  - c(active, ignores), drop=FALSE]) # 2.11
        }
        gam <- c((Cmax - C)/(A - a), (Cmax + C)/(A + a)) # 2.13
### Any dropouts will have gam=0, which are ignored here
        gamhat <- min(min(gam[gam > eps],na.rm=TRUE), Cmax/A)	# 2.13
      }
      if(type == "lasso") {
        dropid <- NULL
        b1 <- beta[k, active]	# beta starts at 0
        z1 <-  - b1/w
        zmin <- min(z1[z1 > eps], gamhat)
        if(zmin < gamhat) {
          gamhat <- zmin
          drops <- z1 == zmin
        }
        else drops <- FALSE
      }
      beta[k + 1,  ] <- beta[k,  ] # keeping all the beta for the next step
      beta[k + 1, active] <- beta[k + 1, active] + gamhat * w # inside 2.12, for each beta of the mu
      if(use.Gram) {
        Cvec <- Cvec - gamhat * Gram[, active, drop = FALSE] %*% w
      }
      else {
        residuals <- residuals - gamhat * u # paragraph of 2.3
        Cvec <- drop(t(residuals) %*% x) # 2.8
      }
      Gamrat <- c(Gamrat, gamhat/(Cmax/A)) # 2.21 + 2.22
      arc.length <- c(arc.length, gamhat)	
### Check if we have to drop any guys
      if(type == "lasso" && any(drops)) {
        dropid <- seq(drops)[drops]	
                                        #turns the TRUE, FALSE vector into numbers
        for(id in rev(dropid)) {
          if(trace)
            cat("Lasso Step", k+1, ":\t Variable", active[
                                                        id], "\tdropped\n")
          R <- downdateR(R, id)
        }
        dropid <- active[drops]	# indices from 1:m
        beta[k+1,dropid]<-0  # added to make sure dropped coef is zero
        active <- active[!drops]
        Sign <- Sign[!drops]
      }
      if(!is.null(vn))
        names(action) <- vn[abs(action)]
      actions[[k]] <- action
      inactive <- im[ - c(active, ignores)]
      if(type=="stepwise")Sign=Sign*0
    }
  beta <- beta[seq(k + 1), ,drop=FALSE ]	#
  lambda=lambda[seq(k)]
  dimnames(beta) <- list(paste(0:k), vn)	### Now compute RSS and R2
  if(trace)
    cat("Computing residuals, RSS etc .....\n")
  residuals <- y - x %*% t(beta)
  beta <- scale(beta, FALSE, normx)
  RSS <- apply(residuals^2, 2, sum)
  R2 <- 1 - RSS/RSS[1]
  actions=actions[seq(k)]
  netdf=sapply(actions,function(x)sum(sign(x)))
  df=cumsum(netdf)### This takes into account drops
  if(intercept)df=c(Intercept=1,df+1)
  else df=c(Null=0,df)
  rss.big=rev(RSS)[1]
  df.big=n-rev(df)[1]
  if(rss.big<eps|df.big<eps)sigma2=NaN
  else
    sigma2=rss.big/df.big
  Cp <- RSS/sigma2 - n + 2 * df
  attr(Cp,"sigma2")=sigma2
  attr(Cp,"n")=n
  object <- list(call = call, type = TYPE, df=df, lambda=lambda,R2 = R2, RSS = RSS, Cp = Cp, 
                 actions = actions[seq(k)], entry = first.in, Gamrat = Gamrat, 
                 arc.length = arc.length, Gram = if(use.Gram) Gram else NULL, 
                 beta = beta, mu = mu, normx = normx, meanx = meanx)
  class(object) <- "lars"
  object
}

