# What is DBmarlin?

DBmarlin is a next-generation database monitoring solution to help your database run fast and stay fast.

# License

DBmarlin is licensed using a Freemium model where the first database you monitor is free forever. If you want to cover additional databases then a subscription is available from [DBmarlin.com](https://www.dbmarlin.com/pricing). We have tried to keep our licensing model simple by charging per database instance, no matter what type of database you are running and irrespective of the number of CPU's or amount of RAM, which will be refreshing for those who have experienced these cumbersome license models before.

# Architecture

![Architecture](https://docs.dbmarlin.com/assets/images/dbmarlin-architecture-88f4261a36579cf80fe24b24fe22f378.svg)

# How To

Download image 

```
docker pull alephp/dbmarlin:release

``` 

Run

``` 

docker run -p 9090:9090  -e size=XSmall --rm  alephp/dbmarlin:release

```

