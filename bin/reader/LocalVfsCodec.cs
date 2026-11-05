using System;
using System.Buffers.Binary;
using AnimeStudio.Endfield;
public static class LocalVfsCodec {
 public static byte[] MetadataPlain(byte[] input) {
  var result=input.AsSpan(12).ToArray();
  new EndfieldChaCha20(EndfieldVfsKeys.ChaChaKey,input.AsSpan(0,12),1).ApplyKeystream(result);
  return result;
 }
 public static byte[] MetadataPack(byte[] originalHeader,byte[] plain) {
  BinaryPrimitives.WriteUInt32LittleEndian(plain.AsSpan(plain.Length-4),EndfieldCrc32.Compute(plain.AsSpan(0,plain.Length-4)));
  var result=new byte[12+plain.Length];originalHeader.AsSpan(0,12).CopyTo(result);
  plain.CopyTo(result,12);
  new EndfieldChaCha20(EndfieldVfsKeys.ChaChaKey,result.AsSpan(0,12),1).ApplyKeystream(result.AsSpan(12));return result;
 }
 public static byte[] FileCrypt(byte[] input,long seed) {
  var result=(byte[])input.Clone();Span<byte> nonce=stackalloc byte[12];
  BinaryPrimitives.WriteInt32LittleEndian(nonce,3);BinaryPrimitives.WriteInt64LittleEndian(nonce.Slice(4),seed);
  new EndfieldChaCha20(EndfieldVfsKeys.ChaChaKey,nonce,1).ApplyKeystream(result);return result;
 }
}
