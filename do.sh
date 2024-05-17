#!/bin/bash
# vim: ts=3

COUNTRIES=('hu' 'de')	# only these countries can connect to below ports
PORTS=('993' '21115' '21116' '21117')	# IMAP, RustDesk
IFACE="ens3"	# internet facing network interface

BASE_DIR="$(dirname $0)"
COUNTRIES_DIR="${BASE_DIR}/countries"

v4listAllowed="countries_allowed_v4"
v6listAllowed="countries_allowed_v6"

function downloadCountries() {
	echo Updating IP ranges from ipdeny.com

	mkdir -p ${COUNTRIES_DIR}
	#rm ${COUNTRIES_DIR}/*

	for country in "${COUNTRIES[@]}"; do
		echo -n "Download '${country}' country..."
		wget -q "https://www.ipdeny.com/ipblocks/data/aggregated/${country}-aggregated.zone" -O ${COUNTRIES_DIR}/${country}.ipv4 && \
		sleep 1s && \
		wget -q "https://www.ipdeny.com/ipv6/ipaddresses/aggregated/${country}-aggregated.zone" -O ${COUNTRIES_DIR}/${country}.ipv6 && \
		sleep 1s && \
		echo OK || echo ERROR
	done
}

function updatesCountryList() {
	echo Creating ipsets
	ipset -exist create "${v4listAllowed}" hash:net family inet
	ipset -exist create "${v6listAllowed}" hash:net family inet6

	echo Flushing ipsets
	ipset flush ${v4listAllowed}
	ipset flush ${v6listAllowed}

	for country in "${COUNTRIES[@]}"; do
		echo Country: ${country}

		#v4list="countries_${country}_v4"
		#v6list="countries_${country}_v6"

		#echo Creating ipsets
		#ipset -exist create "${v4list}" hash:net family inet
		#ipset -exist create "${v6list}" hash:net family inet6

		#echo Flushing ipsets
		#ipset flush ${v4list}
		#ipset flush ${v6list}

		echo Adding IPv4 addresses
		for ip in $(cat ${COUNTRIES_DIR}/${country}.ipv4);  do
        #ipset add "${v4list}" "${ip}"
        ipset add "${v4listAllowed}" "${ip}"
   	done

		echo Adding IPv6 addresses
		for ip in $(cat ${COUNTRIES_DIR}/${country}.ipv6);  do
        #ipset add "${v6list}" "${ip}"
        ipset add "${v6listAllowed}" "${ip}"
   	done
	done

	if [ "${1}" == "update" ]; then
		echo 'Saving ipsets into ipset-persistent (/etc/iptables/ipsets)'
		ipset save > /etc/iptables/ipsets
	fi
}

function initIpTables() {
	echo Configuring iptables

	CHAIN_NAME="my-ipset-rules"

	# IPv4
	iptables -N ${CHAIN_NAME} && \
		iptables -I INPUT -j ${CHAIN_NAME} && \
		iptables -I FORWARD -j ${CHAIN_NAME}
	iptables -v -F ${CHAIN_NAME}

	# IPv6
	ip6tables -N ${CHAIN_NAME} && \
		ip6tables -I INPUT -j ${CHAIN_NAME} && \
		ip6tables -I FORWARD -j ${CHAIN_NAME}
	ip6tables -v -F ${CHAIN_NAME}

	for port in "${PORTS[@]}"; do
		echo "PORT: ${port}"

		# IPv4 - tcp
		iptables -I ${CHAIN_NAME} -i ${IFACE} -p tcp --dport ${port} -m set ! --match-set "${v4listAllowed}" src -j DROP -m comment --comment "Block unknown country (v4)"
		iptables -I ${CHAIN_NAME} -i ${IFACE} -p tcp --dport ${port} -m set ! --match-set "${v4listAllowed}" src -j LOG -m comment --comment "Block unknown country (v4)" --log-prefix "Block unknown country"
		# IPv4 - udp
		iptables -I ${CHAIN_NAME} -i ${IFACE} -p udp --dport ${port} -m set ! --match-set "${v4listAllowed}" src -j DROP -m comment --comment "Block unknown country (v4)"
		iptables -I ${CHAIN_NAME} -i ${IFACE} -p udp --dport ${port} -m set ! --match-set "${v4listAllowed}" src -j LOG -m comment --comment "Block unknown country (v4)" --log-prefix "Block unknown country"
	
		# IPv6 - tcp
		ip6tables -I ${CHAIN_NAME} -i ${IFACE} -p tcp --dport ${port} -m set ! --match-set "${v6listAllowed}" src -j DROP -m comment --comment "Block unknown country (v6)"
		ip6tables -I ${CHAIN_NAME} -i ${IFACE} -p tcp --dport ${port} -m set ! --match-set "${v6listAllowed}" src -j LOG -m comment --comment "Block unknown country (v6)" --log-prefix "Block unknown country"
		# IPv6 - udp
		ip6tables -I ${CHAIN_NAME} -i ${IFACE} -p udp --dport ${port} -m set ! --match-set "${v6listAllowed}" src -j DROP -m comment --comment "Block unknown country (v6)"
		ip6tables -I ${CHAIN_NAME} -i ${IFACE} -p udp --dport ${port} -m set ! --match-set "${v6listAllowed}" src -j LOG -m comment --comment "Block unknown country (v6)" --log-prefix "Block unknown country"
	done
}

echo Countires directory: ${COUNTRIES_DIR}

case ${1} in

  iptables)
	 initIpTables
    ;;

  ipset)
	 updatesCountryList
    ;;

  download)
	 downloadCountries
    ;;

  *)
    echo 'Select one option!'
	 echo '1) iptables	- create required iptables chanin and rules'
	 echo '2) ipset 		- create ip sets based on the already downloaded country secific IP lists'
    echo '3) download	- download contry specific IP lists from ipdeny.com'
    ;;
esac

