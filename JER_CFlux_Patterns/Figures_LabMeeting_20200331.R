###################################################
# Make figures for SEL Lab Meeting, 31 March 2020 #
#      Show air temp, precip, C flux patterns     #
#    focus on:                                    #
#     * seasonal and interannual daily flux       #
#     * yearly cumulative flux                    #
###################################################

# Data to use: 
# EddyPro and EddyRe processed and gap-filled NEE data
# Biomet 1 climate data that contains site-level averages

# known issues as of 27 March 2020: 
# * timestamp shift in tower and SN data (can be fixed: "~/Desktop/R/R_programs/Tweedie/Jornada/Jornada_Tweedie/Jornada Climate Data/test_fixingTimestamps.R")
# * 2010 flux gap-fill missing because Rs data is missing. Gap-fill with NRCS data!! (can be done, got derailed by time-stamps)


# load libraries
library(REddyProc)
library(data.table)
library(lubridate)
library(gridExtra)
library(dplyr)
library(ggplot2)
library(gtable)
library(grid)
library(zoo)
library(bit64)
library(viridis)

# import filtered flux data file from Eddy Pro as data table
# filtered in: Jornada_EddyPro_Output_Fluxnext_2010_2019.R
ep.units <- (fread("~/Desktop/TweedieLab/Projects/Jornada/EddyCovariance/ReddyProc/20200212/REddyResults_US-Jo1_20200213_725822790/output.txt",
                   header=TRUE))[1,]

flux.ep <- fread("~/Desktop/TweedieLab/Projects/Jornada/EddyCovariance/ReddyProc/20200212/REddyResults_US-Jo1_20200213_725822790/output.txt",
                 header=FALSE, skip=2,na.strings=c("-9999", "NA","-"),
                 col.names = colnames(ep.units))

# for some reason na.strings won't recognize the -9999
flux.ep[flux.ep == -9999] <- NA

# get the 'edata' to add 2010 to the timeseries eventhough 2010 won't gap fill.... 
setwd("~/Desktop/TweedieLab/Projects/Jornada/EddyCovariance/JER_Out_EddyPro_filtered")

# import data that was filtered by 3SD filter
load("JER_flux_2010_2019_EddyPro_Output_filtered_SD_20200212.Rdata")

# convert date to POSIXct and get a year, day, hour column
# if this step doesn't work, make sure bit64 library is loaded otherwise the timestamps importa in a non-sensical format
flux_filter_sd[,':=' (date_time = parse_date_time(TIMESTAMP_START,"YmdHM",tz="UTC"),
                      date_time_end = parse_date_time(TIMESTAMP_END,"YmdHM",tz="UTC"))][
                        ,':='(Year_end = year(date_time_end),Year=year(date_time),DoY=yday(date_time),
                              hours = hour(date_time), mins = minute(date_time))]

# there's duplicated data in 2012 DOY 138
flux_filter <- (flux_filter_sd[!(duplicated(flux_filter_sd, by=c("TIMESTAMP_START")))])

# format data columns for ReddyProc
# Year	DoY	Hour	NEE	LE	H	Rg	Tair	Tsoil	rH	VPD	Ustar 
flux_filter[mins==0, Hour := hours+0.0]
flux_filter[mins==30, Hour := hours+0.5]

edata <- flux_filter[,.(Year,
                        DoY,
                        Hour,
                        FC,
                        LE,
                        H,
                        SW_IN_1_1_1,
                        TA_1_1_1,
                        RH_1_1_1,
                        USTAR)]

setnames(edata,c("FC","LE","H","SW_IN_1_1_1","TA_1_1_1","RH_1_1_1","USTAR"),
         c("NEE_orig","LE_orig","H_orig","Rg_orig","Tair_orig","rH_orig","Ustar"))

# make all Rg<0 equal to 0 becuase ReddyProc won't accept values <0
edata[Rg<0, Rg:=0]

# create a grid of full dates and times
filled <- expand.grid(date=seq(as.Date("2010-01-01"),as.Date("2019-12-31"), "days"),
                      Hour=seq(0,23.5, by=0.5))
filled$Year <- year(filled$date)
filled$DoY <- yday(filled$date)

filled$date <- NULL

edata <- merge(edata,filled,by=c("Year","DoY","Hour"), all=TRUE)

# online tool says hours must be between 0.5 and 24.0 
# therefore add 0.5 to each hour
edata[,Hour := Hour+0.5]

# convert edata to data frame for ReddyProc
edata <- as.data.frame(edata)

# calculate VPD from rH and Tair in hPa (mbar), at > 10 hPa the light response curve parameters change
edata$VPD <- fCalcVPDfromRHandTair(edata$rH, edata$Tair)

# get only 2010 and go back to data table
edata2010 <- as.data.table(subset(edata,Year==2010))

flux.ep <- rbind(edata2010,flux.ep, fill=TRUE)

# Plot the measured and U50 gap-filled data
ggplot(subset(flux.ep), aes(DoY,NEE_orig))+
  geom_line(colour="#440154FF")+
  geom_point(aes(y=NEE_U50_f),data=subset(flux.ep, is.na(NEE_orig)),colour="#55C667FF",size=0.15)+
  scale_x_continuous(breaks =c(31,61,91,121,151,181,211,241,271,301,331,361),limits=c(1,367),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"),
                     expand=c(0,0))+
  labs(y=expression("Half-hourly NEE (μmol C" *O[2]*" "*m^-2* "se" *c^-1*")"),
       x = "Month")+
  facet_grid(.~Year)+
ylim(c(-10,10))+
  theme_bw()


# calculate daily sums of Co2 flux in umol/m2/sec converted to gC/m2/day
daily_sum_dt <- as.data.table(subset(flux.ep))
daily_sum <- daily_sum_dt[,list(NEE_daily = sum(NEE_U50_f*1800*1*10^-6*12.01),
                                GPP_daily = sum(GPP_U50_f*1800*1*10^-6*12.01),
                                Reco_daily = sum(Reco_U50*1800*1*10^-6*12.01),
                                Tair_mean = mean(Tair)), 
                          by="Year,DoY"]

# create a running mean 
daily_sum[,NEE_daily_roll := rollmean(x=NEE_daily,
                                      k=7,
                                      fill=NA)]

# add a date variable to daily_sum
daily_sum[Year==2010,date:= as.Date(DoY-1, origin = "2010-01-01")]
daily_sum[Year==2011,date:= as.Date(DoY-1, origin = "2011-01-01")]
daily_sum[Year==2012,date:= as.Date(DoY-1, origin = "2012-01-01")]
daily_sum[Year==2013,date:= as.Date(DoY-1, origin = "2013-01-01")]
daily_sum[Year==2014,date:= as.Date(DoY-1, origin = "2014-01-01")]
daily_sum[Year==2015,date:= as.Date(DoY-1, origin = "2015-01-01")]
daily_sum[Year==2016,date:= as.Date(DoY-1, origin = "2016-01-01")]
daily_sum[Year==2017,date:= as.Date(DoY-1, origin = "2017-01-01")]
daily_sum[Year==2018,date:= as.Date(DoY-1, origin = "2018-01-01")]
daily_sum[Year==2019,date:= as.Date(DoY-1, origin = "2019-01-01")]




# Plot cumulative sum with 7 day running mean
ggplot(daily_sum[Year>2010,], aes(DoY, NEE_daily))+
  geom_line(colour="#55C667FF")+
  geom_line(aes(yday(date),NEE_daily_roll),colour="#440154FF")+
  geom_hline(yintercept=0)+
  scale_x_continuous(breaks =c(31,61,91,121,151,181,211,241,271,301,331,361),limits=c(1,367),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"),
                     expand=c(0,0))+
  labs(y=expression("Daily cumulative NEE (gC" *m^-2*")"),
       x="Month")+
  facet_grid(.~Year)+
  theme_bw()


# plot daily precip
precip_daily <- flux_filter[!is.na(P_RAIN_1_1_1),list(precip.tot = sum(P_RAIN_1_1_1)),
                            by="Year,DoY"]

# add a date variable to daily precip
precip_daily[Year==2010,date:= as.Date(DoY-1, origin = "2010-01-01")]
precip_daily[Year==2011,date:= as.Date(DoY-1, origin = "2011-01-01")]
precip_daily[Year==2012,date:= as.Date(DoY-1, origin = "2012-01-01")]
precip_daily[Year==2013,date:= as.Date(DoY-1, origin = "2013-01-01")]
precip_daily[Year==2014,date:= as.Date(DoY-1, origin = "2014-01-01")]
precip_daily[Year==2015,date:= as.Date(DoY-1, origin = "2015-01-01")]
precip_daily[Year==2016,date:= as.Date(DoY-1, origin = "2016-01-01")]
precip_daily[Year==2017,date:= as.Date(DoY-1, origin = "2017-01-01")]
precip_daily[Year==2018,date:= as.Date(DoY-1, origin = "2018-01-01")]
precip_daily[Year==2019,date:= as.Date(DoY-1, origin = "2019-01-01")]


fig_daily_rain <- ggplot(precip_daily, aes(DoY, precip.tot))+
  geom_line(colour="blue")+
  labs(y="Daily Total Rain (mm)")+
  facet_grid(.~Year)+
  theme_bw()

grid.arrange(fig_daily_NEE,fig_daily_rain, nrow=2)


# calculate monthly precipitation
flux_filter[,month:=month(date_time_end)]
precip_monthly <- flux_filter[!is.na(P_RAIN_1_1_1),list(precip.tot = sum(P_RAIN_1_1_1)),
                              by="month,Year"][Year>2010,precip.cum:=cumsum(precip.tot),by="Year"]

precip_monthly[,year_lab := ifelse(month==12, Year, NA)]


# Graph annual distribution of monthly data
ggplot(precip_monthly, aes(month,precip.tot,fill=factor(month)))+
  geom_boxplot()+
  labs(y="Total Rainfall (mm)", x="Month")+
  scale_x_continuous(breaks=c(seq(1,12,1)),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"))+
  scale_fill_viridis_d()+
  theme_bw()+
  theme(legend.position="none")

# Graph monthly cumulatives
ggplot(precip_monthly[Year!=2010,], aes(month,precip.cum,colour=factor(Year)))+
  geom_point()+
  geom_line()+
  geom_label(aes(label=year_lab))+
  labs(y="Cummulative Rainfall (mm)", x="Month")+
  scale_x_continuous(breaks=c(seq(1,12,1)),
                              labels=c("J","F","M","A","M","J","J","A","S","O","N","D"))+
  scale_colour_viridis_d()+
  theme_bw()+
  theme(legend.position="none")


# calculate monthly air temp
temp_monthly <- flux_filter[!is.na(TA_1_1_1),list(mean.temp = mean(TA_1_1_1),
                                  min.temp = min(TA_1_1_1),
                                  max.temp = max(TA_1_1_1)),
                              by="month,Year"]

# Graph annual distribution of monthly data
ggplot(temp_monthly, aes(month,mean.temp,fill=factor(month)))+
  geom_boxplot()+
  geom_hline(yintercept=0)+
  ylim(c(-25,42))+
  labs(y=expression("Mean Temperature ("~degree~"C)"), x="Month")+
  scale_x_continuous(breaks=c(seq(1,12,1)),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"))+
  scale_fill_viridis_d()+
  theme_bw()+
  theme(legend.position="none")


# Graph annual distribution of Min monthly temp data
ggplot(temp_monthly, aes(month,min.temp,fill=factor(month)))+
  geom_boxplot()+
  geom_hline(yintercept=0)+
  ylim(c(-25,42))+
  labs(y=expression("Minimum Temperature ("~degree~"C)"), x="Month")+
  scale_x_continuous(breaks=c(seq(1,12,1)),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"))+
  scale_fill_viridis_d()+
  theme_bw()+
  theme(legend.position="none")

# Graph annual distribution of Max monthly temp data
ggplot(temp_monthly, aes(month,max.temp,fill=factor(month)))+
  geom_boxplot()+
  geom_hline(yintercept=0)+
  ylim(c(-25,42))+
  labs(y=expression("Maximum Temperature ("~degree~"C)"), x="Month")+
  scale_x_continuous(breaks=c(seq(1,12,1)),
                     labels=c("J","F","M","A","M","J","J","A","S","O","N","D"))+
  scale_fill_viridis_d()+
  theme_bw()+
  theme(legend.position="none")

# graph 'climate envelopes'
monthly.p.t <- merge(precip_monthly,temp_monthly,by=c("Year","month"))
monthly.p.t <- rbind(monthly.p.t,
      data.frame(precip.tot=c(25,25,75),mean.temp=c(5,20,25),env_lab=c("Cool, Dry","Warm, Dry","Warm, Wet")),
      fill=TRUE)

ggplot(monthly.p.t, aes(mean.temp,precip.tot,colour=factor(month)))+
  geom_point(size=3)+
  geom_label(aes(label=env_lab),colour="black")+
  labs(x=expression("Mean Temperature ("~degree~"C)"), y="Rainfall (mm)")+
  scale_color_viridis_d(name="Month",
                       labels=c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"),
                       option="plasma")+
  theme_bw()+
  guides(name="Month")

# Annual total precip
annual_rain <- precip_daily[!is.na(precip.tot),list(precip.ann = sum(precip.tot)),
                            by="Year"]

# plot the annual C and rain budgets
ggplot(annual_rain, aes((Year),precip.ann))+
  geom_line()+
  geom_point(aes(colour=factor(Year)),size=3)+
  labs(y="Annual cumulative Rain, mm")+
  scale_x_continuous(breaks=c(2010,2011,2012,2013,2014,2015,2016,2017,2018,2019),
                     labels=c(2010,2011,2012,2013,2014,2015,2016,2017,2018,2019))+
  theme_bw()


# SEASONAL: plot the daily NEE values by month and year
daily_sum[,month:=month(date)]

ggplot(daily_sum, aes(factor(DoY), NEE_daily, colour=factor(month)))+
  geom_boxplot()+
  geom_hline(yintercept=0)+
  scale_color_viridis_d(option="plasma")+
  scale_x_discrete(breaks =c("31","61","91","121","151","181","211","241","271","301","331","361"),
                   labels=c("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"))+
  labs(y=expression("Daily cumulative NEE (gC" *m^-2*")"),
       x="Month")+
  theme_bw()+
  theme(legend.position="none")


# plot the annual C flux budgets as a monthly cumulative
# calculate cumulative sums
daily_cum_sum <- daily_sum[,':='(NEE_cum = cumsum(NEE_daily),
                                 GPP_cum = cumsum(GPP_daily),
                                 Reco_cum = cumsum(Reco_daily)),
                           by="Year"]

daily_cum_sum[,year_lab := ifelse(yday(date)==365, Year, NA)]


ggplot(daily_cum_sum, aes(DoY,NEE_cum,colour=factor(Year)))+
  geom_line()+
  geom_point()+
  geom_label(aes(label=year_lab))+
  labs(y=expression("Annual cumulative NEE (gC" *m^-2*")"))+
  scale_colour_viridis_d()+
  theme_bw()+
  theme(legend.position="none")


# calculate annual budget
annual_sum <- daily_sum[,list(NEE_annual = sum(NEE_daily)),
                        by="Year"]

# plot the annual budgets
ggplot(annual_sum, aes(factor(Year),NEE_annual,fill=factor(Year)))+
  geom_bar(stat="identity")+
  labs(y=expression("Annual cumulative NEE (gC" *m^-2*")"),x="Year")+
  scale_fill_viridis_d()+
  theme_bw()+
  theme(legend.position="none")

# saved daily and annual sums
#"~/Desktop/TweedieLab/Projects/Jornada/EddyCovariance/ReddyProc/"
#"JER_ReddyProc_daily_sum_CO2_2011_2018.csv"
#"JER_ReddyProc_annual_sum_CO2_2011_2018.csv"