#!/bin/bash


# столкнулся с тем, что диски определяются по-разному. Сначала системный диск sda, потом при следующем включении sdf, потом опять sda, что мешает работать. Потому, выполним следующие действия.
# Определяем, как в системе определяются диски.
# Для этого, определяем, какие диски имеют точку монтирования и инвертируем наш выбор.
# Результат помещаем в массив. Следующим действием создадим переменную с перечислением наших устройств через пробел.
# здесь нам всё равно, как диски определились в ситеме, хоть sdy, всё будет сделано автоматом.
# может это и не красиво, но я не гуру.
array=$(for i in $(mount -l | grep "/dev/sd"  | awk '{print $1}' | cut -c 6-8); do lsblk | grep -v $i | grep sd | awk '{print $1}' | sed "s/sd/\/dev\/sd/g"; done)
diski=$(echo $array)

# Занулим суперблоки наших дисков
mdadm --zero-superblock --force $diski

# создаём рейд-массив md0. Я создаю Raid 6.
mdadm --create --verbose /dev/md0 -l 6 -n 5 $diski

# проверяем, есть ли такой рейд и активен ли он
if cat /proc/mdstat | grep active
    then
        echo "$(cat /proc/mdstat | grep active | awk '{print $4}') собран" > /var/log/raid_create.log
        echo "Имя: $(cat /proc/mdstat | grep active | awk '{print $1}')" >> /var/log/raid_create.log
        echo "Собран из: $(cat /proc/mdstat | grep active | awk '{print $5 " " $6, $7, $8, $9}')" >> /var/log/raid_create.log
        # создаём mdadm.conf
        mkdir /etc/mdadm
        echo "DEVICE partitions" > /etc/mdadm/mdadm.conf
        mdadm --detail --scan --verbose | awk '/ARRAY/{print}' >> /etc/mdadm/mdadm.conf
        # Создаём разметку
        parted -s /dev/md0 mklabel gpt
        echo "таблица разделов успешно создана" >> /var/log/raid_create.log
        # создаём 2 раздела
        parted /dev/md0 mkpart primary ext4 0% 20% -s
        parted /dev/md0 mkpart primary ext4 20% 100% -s
        # Форматирем их
        for i in $(seq 1 2); do mkfs.ext4 /dev/md0p$i; done
        # Создаём каталоги для монтирования
        mkdir -p /media/raid/part{1,2}
        #
        file="/etc/fstab"
        for i in $(seq 1 2); do raid_disks=$(echo /dev/md0p$i); puti=$(echo "/media/raid/part$i"); fstab_v=$(echo $raid_disks $puti ext4 defaults 0 0); if ! grep -q "$fstab_v" "$file"; then echo "$fstab_v" >> "$file"; fi; done
        mount -a
        for i in $(df -h | grep /dev/md0p | awk '{print $1}')
            do
                if ! [ -z $(echo $(echo $(df -h | grep /dev/md0p | awk '{print $1}')) | awk '{print $1}')]
                    then
                        echo $i "успешно смонтирован" >> /var/log/raid_create.log
                    else
                        echo "Диски не смонтированны" >> /var/log/raid_create.log
                fi  
        done
    else
        echo "Raid не собран. Проверьте ошибки." > /var/log/raid_create.log
fi
