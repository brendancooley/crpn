################################################################################
###
### Replication of Morrow 2007, "When Do States Follow the Laws of War?,"
### replacing CINC ratio with DOE scores
###
### Replicating Table 1, Column 1 (unweighted)
###
################################################################################

library("caret")
library("dplyr")
library("foreign")
library("MASS")

## custom ordered probit function for caret call
source("ordered-probit.r")

raw_morrow_2007 <- read.dta("morrow-2007.dta")
doe_dir_dyad <- read.csv("../R/results-predict-dir-dyad.csv")

## remove cases dropped in the analysis
raw_morrow_2007 <- raw_morrow_2007[raw_morrow_2007$data_quality > 0 &
                                     !is.na(raw_morrow_2007$data_quality) &
                                     raw_morrow_2007$WarDeclaration == 0,]

## turn DV into a factor for polr
raw_morrow_2007$factorDV <- factor(raw_morrow_2007$violator_4_ordinal_comply,
                                   levels = 1:4,
                                   labels = c("None", "Low", "Medium", "High"),
                                   ordered = TRUE)

## replication on the full data to establish the result.
f_morrow_2007 <-
  factorDV ~ victim_4_ordinal_comply + victim_clar_4_ordinal_comply +
  joint_ratify_4_ordinal_recip + joint_ratify_clar_recip +
  victim_individual_comply + victim_state_comply +   joint_ratify +
  violator_ratified + violator_democracy7 +   joint_ratify_democracy7 +
  violator_ratified_democracy7 + powerratio +   joint_ratify_power + Aerial +
  Armistice + CBW + Civilians + Cultural +   HighSeas + POWs +
  violator_initiate + violator_deathsper1000population +   victim_victor +
  victim_victor_power

## check results
reported_model <- polr(formula = f_morrow_2007,
                       data = raw_morrow_2007,
                       method = "probit")        ## identical to reported

summary(reported_model)

## drop observations for which we do not have DOE scores (coalitions)
data_morrow_2007 <- raw_morrow_2007[raw_morrow_2007$violatorccode < 1000 &
                                      raw_morrow_2007$victimccode < 1000,]
## went from 1066 observations to 864 observations

## merge in the DOE data
data_morrow_2007 <- left_join(data_morrow_2007,
                              doe_dir_dyad,
                              by = c(violatorccode = "ccode_a",
                                     victimccode = "ccode_b",
                                     startyear = "year"))

## check the merge
data_morrow_2007 %>%
  filter(!is.na(powerratio) & is.na(VictoryA)) %>%
  dplyr::select(violatorccode, victimccode, startyear)
                                                 # we're good

## need to construct some new interaction terms
data_morrow_2007$victim_victor_VictoryA <- data_morrow_2007$victim_victor *
  data_morrow_2007$VictoryA
data_morrow_2007$victim_victor_VictoryB <- data_morrow_2007$victim_victor *
  data_morrow_2007$VictoryB
data_morrow_2007$joint_ratify_VictoryA <- data_morrow_2007$joint_ratify *
  data_morrow_2007$VictoryA
data_morrow_2007$joint_ratify_VictoryB <- data_morrow_2007$joint_ratify *
    data_morrow_2007$VictoryB

## Analogue of glm_and_cv() for polr models
polr_and_cv <- function(form,
                        data,
                        number = 10,
                        repeats = 10)
{
    ## Fit the original model
    fit <- polr(formula = form,
                data = data,
                method = "probit",
                model = TRUE,
                Hess = TRUE)

    ## Extract individual log-likelihoods
    pred_probs <- predict(fit, type = "probs")
    y <- model.response(model.frame(fit))
    y_col <- match(y, colnames(pred_probs))
    pred_probs <- pred_probs[cbind(seq_along(y), y_col)]
    log_lik <- log(pred_probs)

    ## Cross-validate via caret
    cv <- train(form = form,
                data = data,
                method = caret_oprobit,
                metric = "logLoss",
                trControl = trainControl(
                    method = "repeatedcv",
                    number = number,
                    repeats = repeats,
                    returnData = FALSE,
                    summaryFunction = mnLogLoss,
                    classProbs = TRUE)
                )

    list(log_lik = log_lik,
         summary = coef(summary(fit)),
         cv = cv$results,
         formula = form,
         data = fit$model,
         y = y)
}

## re-run the replication on these smaller data
set.seed(8675309)
cr_morrow_2007 <- polr_and_cv(
  form = f_morrow_2007,
  data = data_morrow_2007,
  number = 10,
  repeats = 100
)
printCoefmat(cr_morrow_2007$summary)

## now run it with the DOE scores, including both interactions
set.seed(5555)
doeFormFull <- update(f_morrow_2007,
                   . ~ . - powerratio - joint_ratify_power -
                     victim_victor_power + VictoryA + VictoryB +
                     victim_victor_VictoryA + joint_ratify_VictoryA +
                     victim_victor_VictoryB + joint_ratify_VictoryB)
doe_morrow_2007 <- polr_and_cv(
  form = doeFormFull,
  data = data_morrow_2007,
  number = 10,
  repeats = 100
)
printCoefmat(doe_morrow_2007$summary)

save(cr_morrow_2007,
     doe_morrow_2007,
     file = "results-morrow-2007.rda")