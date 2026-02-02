(defproject powerschoolwrap "0.1.0-SNAPSHOT"
  :description "PowerSchool schedule fetcher/API proxy"
  :url "https://example.com/FIXME"
  :license {:name "EPL-2.0 OR GPL-2.0-or-later WITH Classpath-exception-2.0"
            :url "https://www.eclipse.org/legal/epl-2.0/"}
  :dependencies [[org.clojure/clojure "1.12.4"]
                 [clj-http "3.13.1"]
                 [cheshire "6.1.0"]
                 [org.clj-commons/hickory "0.7.7"]
                 [ring/ring-jetty-adapter "1.15.3"]
                 [ring/ring-core "1.15.3"]
                 [compojure "1.7.2"]
                 [etaoin "1.1.43"]
                 [hiccup "2.0.0"]]
  :jvm-opts ["-Dfile.encoding=UTF-8"]
  :main ^:skip-aot powerschoolwrap
  :plugins [[com.github.liquidz/antq "RELEASE"]]
  :target-path "target/%s"
  :profiles {:uberjar {:aot :all
                       :jvm-opts ["-Dclojure.compiler.direct-linking=true" "-Dfile.encoding=UTF-8"]}})
