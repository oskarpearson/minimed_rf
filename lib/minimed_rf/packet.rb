module MinimedRF
  class Packet
    attr_accessor :address, :body, :crc, :raw_data, :message_type, :channel, :capture_time, :coding_errors, :packet_type

    def initialize
      coding_errors = 0
    end

    def raw_hex_data
      if @raw_data
        @raw_data.unpack('H*').first
      end
    end

    def data=(data)
      # Address type (first byte of packet):
      # 0xa2 (162) = mysentry
      # 0xa5 (165) = glucose meter (bayer contour)
      # 0xa7 (167) = pump
      # 0xaa (170) = sensor
      # 0xab (171) = sensor2

      @packet_type = data.getbyte(0)

      @address = data.byteslice(1,3).unpack("H*").first

      @message_type = data.getbyte(4)

      @body = data.byteslice(5..-2)
      @crc = data.getbyte(-1)
      @raw_data = data

    end

    def packetdiag
      out = "packetdiag {\ncolwidth=32\n"
      bits = ""
      @raw_data.each_byte do |d|
        bits << "%08b" % d
      end
      (0..(bits.length-1)).each do |idx|
        if bits[idx] == "1"
          out << "#{idx}-#{idx}: [color = \"#eeeeee\", style = \"0,1\"]\n"
        end
      end
      out << "}\n"
    end

    def valid?
      !@raw_data.nil? &&
      @raw_data.length > 4 &&
      (crc.nil? || crc == computed_crc)
    end

    def channel
      @channel || '?'
    end

    def computed_crc
      CRC8::compute(raw_data.bytes[0..-2])
    end

    def encode
      codes = []
      @raw_data.bytes.each { |b|
        codes << CODES[(b >> 4)]
        codes << CODES[b & 0xf]
      }
      # aaaaaabb bbbbcccc ccdddddd
      bits = codes.map {|code| "%06b" % code}.join + "000000000000"
      output = ""
      bits.scan(/.{8}/).each do |byte_bits|
        output << "%02x" % Integer("0b"+byte_bits)
      end
      output
    end

    def local_capture_time
      capture_time ? capture_time.localtime : nil
    end

    def to_s
      msg = to_message
      if msg
        "#{"%02x" % @packet_type} #{address} #{msg}"
      elsif valid?
        "#{"%02x" % @packet_type} #{address} #{"%02x" % message_type} #{body.unpack("H*").first} #{"%02x" % crc} "
      elsif raw_data
        "invalid: #{raw_data.unpack("H*").first} expected_crc=#{"%02x" % computed_crc}"
      else
        "invalid: encoding errors"
      end
    end

    def to_message
      if valid?
        case packet_type
        when 0xa2,0xa7
          if MessageTypeMap.include?(message_type)
            MessageTypeMap[message_type].new(raw_data[5..-2])
          end
        when 0xa5
          MinimedRF::Meter.new(raw_data[4..-2])
        when 0xa8
          # Sensor
        end
      end
    end

    def self.from_hex(hex)
      p = Packet.new
      p.data = [hex].pack('H*')
      p
    end

    def self.decode_from_radio(hex_str)
      p = Packet.new
      coding_errors = 0
      radio_bytes = [hex_str].pack('H*').bytes
      bits = radio_bytes.map {|d| "%08b" % d}.join
      decoded_symbols = []
      bits.scan(/.{6}/).each do |word_bits|
        break if word_bits == '000000'
        symbol = CODE_SYMBOLS[word_bits]
        if symbol.nil?
          coding_errors += 1
        else
          decoded_symbols << symbol
        end
      end
      if decoded_symbols.count > 12
        if decoded_symbols.length.odd?
          decoded_symbols = decoded_symbols[0..-2]
        end
        p.data = [decoded_symbols.join].pack("H*")
      end
      p.coding_errors = coding_errors
      p
    end
  end
end
